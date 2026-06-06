import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'merge_policy.dart';
import 'remote_row_codec.dart';
import 'sync_coordinator.dart';
import 'sync_ids.dart';
import 'sync_operation.dart';

/// Supabase implementation of the outbox push engine with optimistic
/// concurrency.
///
/// Split out of [SupabaseRemotePantryRepository] (which still implements
/// [RemoteSyncGateway] and delegates to this) so the push / version-merge /
/// retry logic — which only needs a [SupabaseClient] and the remote row codecs —
/// lives apart from household management and bulk CRUD/streams.
class SupabaseSyncGateway implements RemoteSyncGateway {
  SupabaseSyncGateway(this._client);

  final SupabaseClient _client;

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
