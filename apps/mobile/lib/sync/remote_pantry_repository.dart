import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config.dart';
import '../household/invite_token.dart';
import '../household/household_models.dart';
import 'merge_policy.dart';
import 'remote_row_codec.dart';
import 'sync_coordinator.dart';
import 'sync_ids.dart';
import 'sync_operation.dart';

abstract class RemotePantryRepository {
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<String> createInvite({required String householdId, String? email});
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId);
  Future<List<HouseholdInvitePreview>> loadPendingInvites();
  Future<HouseholdInvitePreview> previewInvite(String token);
  Future<void> acceptInvite(String token);
  Future<void> acceptInviteById(String inviteId);
  Future<void> removeMember({
    required String householdId,
    required String userId,
  });
  Future<void> revokeInvite(String inviteId);
  Future<void> dissolveHousehold(String householdId);
  Future<void> leaveHousehold(String householdId);
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(String householdId);
  Future<void> updateHouseholdName(String householdId, String name);
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  );
  Future<List<Map<String, dynamic>>> loadInventory(String householdId);
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  );
  Future<List<Map<String, dynamic>>> loadShopping(String householdId);
  Future<List<Map<String, dynamic>>> loadCustomRecipes(String householdId);
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId);
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId);
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId);
}

class SupabaseRemotePantryRepository
    implements RemotePantryRepository, RemoteSyncGateway {
  SupabaseRemotePantryRepository(
    this._client, {
    String apiBaseUrl = defaultFreshPantryApiBaseUrl,
  }) : _apiBaseUrl = apiBaseUrl;

  final SupabaseClient _client;
  final String _apiBaseUrl;

  @override
  Future<List<Household>> loadHouseholds() async {
    final rows = await _client.from('households').select();
    return rows.map(Household.fromJson).toList();
  }

  @override
  Future<Household> createHousehold(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create household without a signed-in user.');
    }

    final row = {
      'id': const Uuid().v4(),
      'name': name,
      'owner_id': userId,
      'default_storage_area': 'fridge',
    };
    await _client.from('households').insert(row);
    await _client.from('household_members').insert({
      'household_id': row['id'],
      'user_id': userId,
      'role': 'owner',
    });
    return Household.fromJson(row);
  }

  @override
  Future<String> createInvite({
    required String householdId,
    String? email,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Cannot create invite without a signed-in user.');
    }

    final trimmedEmail = email?.trim();
    final targetEmail = trimmedEmail == null || trimmedEmail.isEmpty
        ? null
        : trimmedEmail;

    final token = generateInviteToken();
    await _client.from('household_invites').insert({
      'household_id': householdId,
      'email': targetEmail,
      'token_hash': hashInviteToken(token),
      // An open (email-less) invite link is a bearer credential embedded in the
      // shared URL, so give it a short window; an email-bound invite is safer
      // (acceptance re-checks the email) and can live a bit longer.
      'expires_at': DateTime.now()
          .toUtc()
          .add(
            targetEmail == null
                ? const Duration(hours: 24)
                : const Duration(days: 3),
          )
          .toIso8601String(),
      'created_by': userId,
    });
    final baseUrl = _apiBaseUrl.endsWith('/')
        ? _apiBaseUrl.substring(0, _apiBaseUrl.length - 1)
        : _apiBaseUrl;
    return '$baseUrl/invite/$token';
  }

  @override
  Future<List<HouseholdMember>> loadHouseholdMembers(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) return const [];
    if (_client.auth.currentUser == null) {
      throw StateError(
        'Cannot list household members without a signed-in user.',
      );
    }

    final rows = await _client.rpc(
      'list_household_members',
      params: {'target_household_id': trimmedHouseholdId},
    );
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => HouseholdMember.fromJson(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  @override
  Future<List<HouseholdInvitePreview>> loadPendingInvites() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot list pending invites without a signed-in user.');
    }

    final rows = await _client.rpc('list_pending_household_invites');
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map(
          (row) =>
              HouseholdInvitePreview.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Future<HouseholdInvitePreview> previewInvite(String token) async {
    final trimmedToken = token.trim();
    if (!isInviteTokenShapeValid(trimmedToken)) {
      throw ArgumentError.value(token, 'token', 'Invalid invite token');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot preview invite without a signed-in user.');
    }

    final rows = await _client.rpc(
      'preview_household_invite',
      params: {'invite_token_hash': hashInviteToken(trimmedToken)},
    );
    if (rows is! List || rows.isEmpty || rows.first is! Map) {
      throw StateError('Invite preview is not available.');
    }

    return HouseholdInvitePreview.fromJson(
      Map<String, dynamic>.from(rows.first as Map),
    );
  }

  @override
  Future<void> acceptInvite(String token) async {
    final trimmedToken = token.trim();
    if (!isInviteTokenShapeValid(trimmedToken)) {
      throw ArgumentError.value(token, 'token', 'Invalid invite token');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot accept invite without a signed-in user.');
    }

    await _client.rpc(
      'accept_household_invite',
      params: {'invite_token_hash': hashInviteToken(trimmedToken)},
    );
  }

  @override
  Future<void> acceptInviteById(String inviteId) async {
    final trimmedInviteId = inviteId.trim();
    if (!isUuid(trimmedInviteId)) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Invalid invite id');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot accept invite without a signed-in user.');
    }

    await _client.rpc(
      'accept_household_invite_by_id',
      params: {'target_invite_id': trimmedInviteId},
    );
  }

  @override
  Future<void> removeMember({
    required String householdId,
    required String userId,
  }) async {
    final trimmedHouseholdId = householdId.trim();
    if (!isUuid(trimmedHouseholdId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    final trimmedUserId = userId.trim();
    if (!isUuid(trimmedUserId)) {
      throw ArgumentError.value(userId, 'userId', 'Invalid user id');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot remove member without a signed-in user.');
    }

    await _client.rpc(
      'remove_household_member',
      params: {
        'target_household_id': trimmedHouseholdId,
        'target_user_id': trimmedUserId,
      },
    );
  }

  @override
  Future<void> leaveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (!isUuid(trimmedHouseholdId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot leave a household without a signed-in user.');
    }
    await _client.rpc(
      'leave_household',
      params: {'target_household_id': trimmedHouseholdId},
    );
  }

  @override
  Future<void> revokeInvite(String inviteId) async {
    final trimmedInviteId = inviteId.trim();
    if (!isUuid(trimmedInviteId)) {
      throw ArgumentError.value(inviteId, 'inviteId', 'Invalid invite id');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot revoke invite without a signed-in user.');
    }

    await _client.rpc(
      'revoke_household_invite',
      params: {'target_invite_id': trimmedInviteId},
    );
  }

  @override
  Future<void> dissolveHousehold(String householdId) async {
    final trimmedHouseholdId = householdId.trim();
    if (!isUuid(trimmedHouseholdId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot dissolve household without a signed-in user.');
    }

    await _client.rpc(
      'dissolve_household',
      params: {'target_household_id': trimmedHouseholdId},
    );
  }

  @override
  Future<List<OwnerPendingInvite>> fetchOwnerPendingInvites(
    String householdId,
  ) async {
    final trimmedHouseholdId = householdId.trim();
    if (trimmedHouseholdId.isEmpty) return const [];
    if (_client.auth.currentUser == null) {
      throw StateError(
        'Cannot list owner pending invites without a signed-in user.',
      );
    }

    final rows = await _client.rpc(
      'list_owner_pending_invites',
      params: {'target_household_id': trimmedHouseholdId},
    );
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map(
          (row) => OwnerPendingInvite.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> updateHouseholdName(String householdId, String name) async {
    final trimmedId = householdId.trim();
    if (!isUuid(trimmedId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError.value(name, 'name', 'Household name cannot be empty');
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot update household without a signed-in user.');
    }

    await _client
        .from('households')
        .update({'name': trimmedName})
        .eq('id', trimmedId);
  }

  @override
  Future<void> updateCategoryPreferences(
    String householdId,
    Map<String, dynamic> preferences,
  ) async {
    final trimmedId = householdId.trim();
    if (!isUuid(trimmedId)) {
      throw ArgumentError.value(
        householdId,
        'householdId',
        'Invalid household id',
      );
    }
    if (_client.auth.currentUser == null) {
      throw StateError('Cannot update preferences without a signed-in user.');
    }

    await _client
        .from('households')
        .update({'category_preferences': preferences})
        .eq('id', trimmedId);
  }

  @override
  Future<List<Map<String, dynamic>>> loadInventory(String householdId) async {
    final rows = await _client
        .from('inventory_items')
        .select()
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    return rows.map(inventoryRowFromJson).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadShopping(String householdId) async {
    final rows = await _client
        .from('shopping_items')
        .select()
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    return rows.map(shoppingRowFromJson).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> loadCustomRecipes(
    String householdId,
  ) async {
    final rows = await _client
        .from('custom_recipes')
        .select()
        .eq('household_id', householdId)
        .isFilter('deleted_at', null);
    return rows.map(customRecipeRowFromJson).toList();
  }

  @override
  Future<void> upsertInventory(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertInventory only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('inventory_items')
        .upsert(
          rows.map((row) => inventoryRowForUpsert(householdId, row)).toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> upsertShopping(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertShopping only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('shopping_items')
        .upsert(
          rows.map((row) => shoppingRowForUpsert(householdId, row)).toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> upsertCustomRecipes(
    String householdId,
    List<Map<String, dynamic>> rows,
  ) async {
    if (rows.isEmpty) return;
    final versioned = rows.where(_hasRemoteVersion).toList();
    if (versioned.isNotEmpty) {
      throw ArgumentError(
        'upsertCustomRecipes only accepts unsynced local rows; versioned sync '
        'writes must use a conditional remote operation.',
      );
    }
    await _client
        .from('custom_recipes')
        .upsert(
          rows
              .map((row) => customRecipeRowForUpsert(householdId, row))
              .toList(),
          ignoreDuplicates: true,
        );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchInventory(String householdId) {
    return _client
        .from('inventory_items')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map((rows) => rows.map(inventoryRowFromJson).toList(growable: false));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchShopping(String householdId) {
    return _client
        .from('shopping_items')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map((rows) => rows.map(shoppingRowFromJson).toList(growable: false));
  }

  @override
  Stream<List<Map<String, dynamic>>> watchCustomRecipes(String householdId) {
    return _client
        .from('custom_recipes')
        .stream(primaryKey: ['id'])
        .eq('household_id', householdId)
        .map(
          (rows) => rows.map(customRecipeRowFromJson).toList(growable: false),
        );
  }

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    final acknowledged = <String>{};
    for (final operation in operations) {
      try {
        await _pushOperation(operation);
      } catch (error, stackTrace) {
        // Stop on the first failure so already-acknowledged operations are
        // removed from the outbox while the failed operation and every
        // operation queued after it stay in FIFO order for the next push.
        _reportPushError(operation, error, stackTrace);
        break;
      }
      acknowledged.add(operation.id);
    }
    return acknowledged;
  }

  Future<void> _pushOperation(SyncOperation operation) {
    return switch (operation.entityType) {
      SyncEntityType.inventoryItem => _pushInventoryOperation(operation),
      SyncEntityType.shoppingItem => _pushShoppingOperation(operation),
      SyncEntityType.customRecipe => _pushCustomRecipeOperation(operation),
      SyncEntityType.householdConfig => Future.value(),
    };
  }

  Future<void> _pushInventoryOperation(SyncOperation operation) async {
    switch (operation.operation) {
      case SyncOperationType.create:
      case SyncOperationType.update:
      case SyncOperationType.intake:
      case SyncOperationType.deduction:
        await _pushVersionedRow(
          'inventory_items',
          operation,
          rowForUpsert: inventoryRowForUpsert,
          rowFromJson: inventoryRowFromJson,
        );
      case SyncOperationType.delete:
        await _softDeleteRemoteRow('inventory_items', operation);
      case SyncOperationType.toggleChecked:
        return;
    }
  }

  Future<void> _pushShoppingOperation(SyncOperation operation) async {
    switch (operation.operation) {
      case SyncOperationType.create:
      case SyncOperationType.update:
      case SyncOperationType.intake:
      case SyncOperationType.deduction:
        await _pushVersionedRow(
          'shopping_items',
          operation,
          rowForUpsert: shoppingRowForUpsert,
          rowFromJson: shoppingRowFromJson,
        );
      case SyncOperationType.toggleChecked:
        await _updateRemoteRow('shopping_items', operation, {
          'is_checked': operation.patch['isChecked'] == true,
        });
      case SyncOperationType.delete:
        await _softDeleteRemoteRow('shopping_items', operation);
    }
  }

  Future<void> _pushCustomRecipeOperation(SyncOperation operation) async {
    switch (operation.operation) {
      case SyncOperationType.create:
      case SyncOperationType.update:
        await _pushVersionedRow(
          'custom_recipes',
          operation,
          rowForUpsert: customRecipeRowForUpsert,
          rowFromJson: customRecipeRowFromJson,
        );
      case SyncOperationType.delete:
        await _softDeleteRemoteRow('custom_recipes', operation);
      case SyncOperationType.intake:
      case SyncOperationType.deduction:
      case SyncOperationType.toggleChecked:
        return;
    }
  }

  /// Writes a full-object create/update with optimistic concurrency.
  ///
  /// Creates (no [SyncOperation.baseVersion]) keep using an idempotent upsert.
  /// Updates to an existing row are gated on the remote `version` matching the
  /// client's [SyncOperation.baseVersion]; if no row matches that version
  /// (someone else advanced it) the current remote row is re-fetched, merged
  /// via [mergeRemotePatch], and written back conditionally with a version
  /// derived from the actual remote version rather than the stale client base.
  Future<void> _pushVersionedRow(
    String table,
    SyncOperation operation, {
    required Map<String, dynamic> Function(String, Map<String, dynamic>)
    rowForUpsert,
    required Map<String, dynamic> Function(Map<String, dynamic>) rowFromJson,
  }) async {
    final entityId = isUuid(operation.entityId)
        ? operation.entityId
        : operation.patch['id'];
    final domain = {
      ...operation.patch,
      'id': entityId,
      'clientUpdatedAt': operation.createdAt.toIso8601String(),
    };

    final baseVersion = operation.baseVersion ?? 0;
    if (baseVersion <= 0) {
      // First write for this row: an idempotent insert is safe and must not
      // downgrade an existing remote version, so leave matching rows untouched.
      final row = rowForUpsert(operation.householdId, {
        ...domain,
        'remoteVersion': 1,
      });
      row['client_id'] = operation.clientId;
      await _client.from(table).upsert(row, ignoreDuplicates: true);
      return;
    }

    if (!(entityId is String && isUuid(entityId))) {
      throw ArgumentError.value(
        operation.entityId,
        'operation.entityId',
        'Versioned remote updates require a UUID entity id.',
      );
    }

    final row = rowForUpsert(operation.householdId, {
      ...domain,
      'remoteVersion': baseVersion + 1,
    });
    row['client_id'] = operation.clientId;
    final updated = await _client
        .from(table)
        .update(row)
        .eq('household_id', operation.householdId)
        .eq('id', entityId)
        .eq('version', baseVersion)
        .select();
    if (updated.isNotEmpty) return;

    // The remote row advanced past baseVersion (concurrent edit) or no longer
    // exists. Resolve against the current remote state.
    await _resolveContendedWrite(
      table,
      operation,
      entityId: entityId,
      localPatch: domain,
      rowForUpsert: rowForUpsert,
      rowFromJson: rowFromJson,
    );
  }

  Future<void> _resolveContendedWrite(
    String table,
    SyncOperation operation, {
    required String entityId,
    required Map<String, dynamic> localPatch,
    required Map<String, dynamic> Function(String, Map<String, dynamic>)
    rowForUpsert,
    required Map<String, dynamic> Function(Map<String, dynamic>) rowFromJson,
  }) async {
    for (var attempt = 0; attempt < _maxConflictRetries; attempt += 1) {
      final current = await _client
          .from(table)
          .select()
          .eq('household_id', operation.householdId)
          .eq('id', entityId)
          .maybeSingle();
      if (current == null) {
        // The row was deleted (or never created) remotely; recreate it from
        // the client patch without clobbering a higher version.
        final row = rowForUpsert(operation.householdId, {
          ...localPatch,
          'remoteVersion': (operation.baseVersion ?? 0) + 1,
        });
        row['client_id'] = operation.clientId;
        await _client.from(table).upsert(row, ignoreDuplicates: true);
        return;
      }

      final remoteVersion = (current['version'] as num?)?.toInt() ?? 0;
      final remote = rowFromJson(current);
      final merge = mergeRemotePatch(
        local: localPatch,
        remote: remote,
        patch: localPatch,
        baseVersion: operation.baseVersion,
        remoteVersion: remoteVersion,
      );
      if (merge.conflict) {
        _reportConflict(table, operation, merge.conflictFields);
      }

      final row = rowForUpsert(operation.householdId, {
        ...merge.value,
        'id': entityId,
        // Derive the authoritative version from the actual remote row, never
        // the stale client base, so the counter only ever moves forward.
        'remoteVersion': remoteVersion + 1,
        'clientUpdatedAt': operation.createdAt.toIso8601String(),
      });
      row['client_id'] = operation.clientId;
      final updated = await _client
          .from(table)
          .update(row)
          .eq('household_id', operation.householdId)
          .eq('id', entityId)
          .eq('version', remoteVersion)
          .select();
      if (updated.isNotEmpty) return;
      // Lost another race; re-read and retry.
    }
    throw StateError(
      'Failed to resolve concurrent edit for $table ${operation.entityId} '
      'after $_maxConflictRetries attempts.',
    );
  }

  Future<void> _softDeleteRemoteRow(
    String table,
    SyncOperation operation,
  ) async {
    final deletedAt = operation.patch['deletedAt'];
    await _updateRemoteRow(table, operation, {
      'deleted_at': deletedAt is String
          ? deletedAt
          : operation.createdAt.toIso8601String(),
    });
  }

  /// Applies a partial column [patch] (toggle/soft-delete) with optimistic
  /// concurrency. The write is gated on the remote `version` matching the
  /// client base; on contention the current row is re-fetched and the patch is
  /// re-applied on top of it with a version derived from the remote row.
  Future<void> _updateRemoteRow(
    String table,
    SyncOperation operation,
    Map<String, dynamic> patch,
  ) async {
    if (!isUuid(operation.entityId)) {
      throw ArgumentError.value(
        operation.entityId,
        'operation.entityId',
        'Remote updates require a UUID entity id.',
      );
    }

    final baseVersion = operation.baseVersion ?? 0;
    if (baseVersion > 0) {
      final updated = await _client
          .from(table)
          .update({
            ...patch,
            'version': baseVersion + 1,
            'client_id': operation.clientId,
            'client_updated_at': operation.createdAt.toIso8601String(),
          })
          .eq('household_id', operation.householdId)
          .eq('id', operation.entityId)
          .eq('version', baseVersion)
          .select();
      if (updated.isNotEmpty) return;
    }

    for (var attempt = 0; attempt < _maxConflictRetries; attempt += 1) {
      final current = await _client
          .from(table)
          .select('version')
          .eq('household_id', operation.householdId)
          .eq('id', operation.entityId)
          .maybeSingle();
      if (current == null) return;
      final remoteVersion = (current['version'] as num?)?.toInt() ?? 0;
      final updated = await _client
          .from(table)
          .update({
            ...patch,
            'version': remoteVersion + 1,
            'client_id': operation.clientId,
            'client_updated_at': operation.createdAt.toIso8601String(),
          })
          .eq('household_id', operation.householdId)
          .eq('id', operation.entityId)
          .eq('version', remoteVersion)
          .select();
      if (updated.isNotEmpty) return;
    }
    throw StateError(
      'Failed to resolve concurrent edit for $table ${operation.entityId} '
      'after $_maxConflictRetries attempts.',
    );
  }

  void _reportConflict(
    String table,
    SyncOperation operation,
    List<String> conflictFields,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: StateError(
          'Resolved concurrent edit on $table ${operation.entityId} '
          '(${operation.operation.name}); client fields won over remote: '
          '${conflictFields.join(', ')}.',
        ),
        library: 'fresh_pantry.sync',
        context: ErrorDescription('while merging a concurrent remote edit'),
      ),
    );
  }

  void _reportPushError(
    SyncOperation operation,
    Object error,
    StackTrace stackTrace,
  ) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'fresh_pantry.sync',
        context: ErrorDescription(
          'while pushing sync operation ${operation.id} '
          '(${operation.entityType.name}/${operation.operation.name})',
        ),
      ),
    );
  }
}

const _maxConflictRetries = 3;

bool _hasRemoteVersion(Map<String, dynamic> row) {
  final version = row['remoteVersion'];
  return version is num && version.toInt() > 0;
}
