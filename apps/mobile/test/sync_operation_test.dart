import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

void main() {
  test('SyncOutboxRepo saves and loads pending operations', () async {
    final repo = SyncOutboxRepo(InMemoryStorageAdapter());
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.shoppingItem,
      entityId: 'item_1',
      operation: SyncOperationType.update,
      patch: const {'isChecked': true},
      baseVersion: 2,
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
      attemptCount: 1,
      lastError: 'timeout',
    );

    await repo.enqueue(operation);

    expect(repo.loadPending(), [operation]);
    final loaded = repo.loadPending().single;
    expect(loaded.patch, {'isChecked': true});
    expect(loaded.attemptCount, 1);
    expect(loaded.lastError, 'timeout');
  });

  test('SyncOutboxRepo removes acknowledged operations', () async {
    final repo = SyncOutboxRepo(InMemoryStorageAdapter());
    final acknowledged = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.inventoryItem,
      entityId: 'item_1',
      operation: SyncOperationType.delete,
      patch: const {},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );
    final pending = SyncOperation(
      id: 'op_2',
      householdId: 'household_1',
      entityType: SyncEntityType.customRecipe,
      entityId: 'recipe_1',
      operation: SyncOperationType.create,
      patch: const {'name': 'Soup'},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 28),
    );

    await repo.enqueue(acknowledged);
    await repo.enqueue(pending);
    await repo.removeAcknowledged({'op_1'});

    expect(repo.loadPending(), [pending]);
  });

  test('SyncOutboxRepo replaces all pending operations', () async {
    final repo = SyncOutboxRepo(InMemoryStorageAdapter());
    final original = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.inventoryItem,
      entityId: 'item_1',
      operation: SyncOperationType.update,
      patch: const {'quantity': '1'},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );
    final replacement = SyncOperation(
      id: 'op_2',
      householdId: 'household_1',
      entityType: SyncEntityType.householdConfig,
      entityId: 'config_1',
      operation: SyncOperationType.update,
      patch: const {'locale': 'zh-CN'},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 28),
    );

    await repo.enqueue(original);
    await repo.replaceAll([replacement]);

    expect(repo.loadPending(), [replacement]);
  });

  test('SyncOutboxRepo ignores malformed local outbox data', () async {
    final adapter = InMemoryStorageAdapter();
    await adapter.write(SyncOutboxRepo.storageKey, '{"not":"a list"}');
    final repo = SyncOutboxRepo(adapter);

    expect(repo.loadPending(), isEmpty);
  });

  test('SyncOperation rejects records missing required fields', () {
    expect(
      () => SyncOperation.fromJson(const {
        'id': 'op_1',
        'householdId': 'household_1',
        'entityType': 'shoppingItem',
        'operation': 'update',
        'patch': {},
        'clientId': 'client_1',
        'createdAt': '2026-05-27T00:00:00.000Z',
      }),
      throwsFormatException,
    );
  });

  test(
    'SyncOutboxRepo refuses to overwrite a corrupted outbox on enqueue',
    () async {
      final adapter = InMemoryStorageAdapter();
      final operation = SyncOperation(
        id: 'op_1',
        householdId: 'household_1',
        entityType: SyncEntityType.shoppingItem,
        entityId: 'item_1',
        operation: SyncOperationType.update,
        patch: const {'isChecked': true},
        clientId: 'client_1',
        createdAt: DateTime.utc(2026, 5, 27),
      );
      final originalRaw = '[{"id":"op_existing","entityType":"unknown"}]';
      await adapter.write(SyncOutboxRepo.storageKey, originalRaw);
      final repo = SyncOutboxRepo(adapter);

      expect(() => repo.enqueue(operation), throwsFormatException);
      expect(adapter.read(SyncOutboxRepo.storageKey), originalRaw);
    },
  );

  test(
    'SyncOutboxRepo refuses to overwrite an outbox with non-object entries',
    () async {
      final adapter = InMemoryStorageAdapter();
      final operation = SyncOperation(
        id: 'op_2',
        householdId: 'household_1',
        entityType: SyncEntityType.shoppingItem,
        entityId: 'item_2',
        operation: SyncOperationType.update,
        patch: const {'isChecked': true},
        clientId: 'client_1',
        createdAt: DateTime.utc(2026, 5, 28),
      );
      final originalRaw =
          '[{"id":"op_1","householdId":"household_1","entityType":"shoppingItem",'
          '"entityId":"item_1","operation":"update","patch":{},'
          '"clientId":"client_1","createdAt":"2026-05-27T00:00:00.000Z"},42]';
      await adapter.write(SyncOutboxRepo.storageKey, originalRaw);
      final repo = SyncOutboxRepo(adapter);

      expect(() => repo.enqueue(operation), throwsFormatException);
      expect(() => repo.removeAcknowledged({'op_1'}), throwsFormatException);
      expect(adapter.read(SyncOutboxRepo.storageKey), originalRaw);
    },
  );

  test('SyncOperation patch is immutable after construction', () {
    final patch = {'isChecked': true};
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.shoppingItem,
      entityId: 'item_1',
      operation: SyncOperationType.update,
      patch: patch,
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );
    final operations = {operation};

    patch['isChecked'] = false;

    expect(operation.patch, {'isChecked': true});
    expect(operations.contains(operation), isTrue);
  });

  test('SyncOperation toJson returns a detached patch copy', () {
    final operation = SyncOperation(
      id: 'op_1',
      householdId: 'household_1',
      entityType: SyncEntityType.shoppingItem,
      entityId: 'item_1',
      operation: SyncOperationType.update,
      patch: const {'isChecked': true},
      clientId: 'client_1',
      createdAt: DateTime.utc(2026, 5, 27),
    );

    final json = operation.toJson();
    (json['patch'] as Map<String, dynamic>)['isChecked'] = false;

    expect(operation.patch, {'isChecked': true});
  });
}
