import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_outbox_repo.dart';

class FakeRemoteSyncGateway implements RemoteSyncGateway {
  final uploaded = <SyncOperation>[];

  @override
  Future<Set<String>> pushOperations(List<SyncOperation> operations) async {
    uploaded.addAll(operations);
    return operations.map((operation) => operation.id).toSet();
  }
}

void main() {
  test(
    'pushPending uploads outbox operations and removes acknowledged ones',
    () async {
      final outbox = SyncOutboxRepo(InMemoryStorageAdapter());
      final remote = FakeRemoteSyncGateway();
      final coordinator = SyncCoordinator(outbox: outbox, remote: remote);
      final operation = SyncOperation(
        id: 'op_1',
        householdId: 'household_1',
        entityType: SyncEntityType.shoppingItem,
        entityId: 'item_1',
        operation: SyncOperationType.toggleChecked,
        patch: const {'isChecked': true},
        clientId: 'client_1',
        createdAt: DateTime.utc(2026, 5, 27),
      );

      await outbox.enqueue(operation);
      await coordinator.pushPending();

      expect(remote.uploaded, [operation]);
      expect(outbox.loadPending(), isEmpty);
    },
  );
}
