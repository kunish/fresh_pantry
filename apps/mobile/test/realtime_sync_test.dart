import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/sync_coordinator.dart';

void main() {
  test('visibleRemoteRows ignores soft-deleted rows', () {
    final rows = [
      {'id': 'item_1', 'name': 'Milk', 'deletedAt': null},
      {'id': 'item_2', 'name': 'Rice', 'deletedAt': '2026-05-27T00:00:00.000Z'},
      {
        'id': 'item_3',
        'name': 'Eggs',
        'deleted_at': '2026-05-27T00:00:00.000Z',
      },
    ];

    final visible = visibleRemoteRows(rows);

    expect(visible.map((row) => row['id']), ['item_1']);
  });
}
