import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/sync/remote_row_codec.dart';

void main() {
  group('round-trip binds encode and decode', () {
    test('inventory: a synced row survives forUpsert → fromJson unchanged', () {
      const domain = {
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Milk',
        'quantity': '1',
        'unit': 'box',
        'imageUrl': 'milk.png',
        'freshnessPercent': 0.5,
        'state': 'urgent',
        'expiryLabel': '2天后过期',
        'category': '乳品蛋类',
        'barcode': '123',
        'storage': 'fridge',
        'expiryDate': '2026-06-01T00:00:00.000Z',
        'addedAt': '2026-05-20T00:00:00.000Z',
        'shelfLifeDays': 7,
        'remoteVersion': 3,
        'clientUpdatedAt': '2026-05-27T00:00:00.000Z',
        'deletedAt': null,
      };

      expect(inventoryRowFromJson(inventoryRowForUpsert('h1', domain)), domain);
    });

    test('shopping: a synced row survives forUpsert → fromJson unchanged', () {
      const domain = {
        'id': '22222222-2222-2222-2222-222222222222',
        'name': 'Eggs',
        'detail': '6 pcs',
        'imageUrl': 'eggs.png',
        'category': '乳品蛋类',
        'isChecked': true,
        'remoteVersion': 5,
        'clientUpdatedAt': '2026-05-27T00:00:00.000Z',
        'deletedAt': null,
      };

      expect(shoppingRowFromJson(shoppingRowForUpsert('h1', domain)), domain);
    });
  });

  test('local-only row (version 0) is promoted to version 1 on round-trip', () {
    final out = inventoryRowFromJson(
      inventoryRowForUpsert('h1', const {
        'id': '11111111-1111-1111-1111-111111111111',
        'name': 'Milk',
        'quantity': '1',
        'unit': 'box',
        'remoteVersion': 0,
      }),
    );

    expect(out['remoteVersion'], 1);
  });
}
