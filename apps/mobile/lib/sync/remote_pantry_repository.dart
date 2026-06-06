import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/backend_config.dart';
import '../household/invite_token.dart';
import '../household/household_models.dart';
import 'remote_row_codec.dart';
import 'supabase_sync_gateway.dart';
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
    SupabaseClient client, {
    String apiBaseUrl = defaultFreshPantryApiBaseUrl,
  })  : _client = client,
        _apiBaseUrl = apiBaseUrl,
        _syncGateway = SupabaseSyncGateway(client);

  final SupabaseClient _client;
  final String _apiBaseUrl;
  final SupabaseSyncGateway _syncGateway;

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
  Future<Set<String>> pushOperations(List<SyncOperation> operations) =>
      _syncGateway.pushOperations(operations);
}

bool _hasRemoteVersion(Map<String, dynamic> row) {
  final version = row['remoteVersion'];
  return version is num && version.toInt() > 0;
}
