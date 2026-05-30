import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';

void main() {
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
