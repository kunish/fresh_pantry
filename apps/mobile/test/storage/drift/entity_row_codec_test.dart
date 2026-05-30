import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/storage/drift/entity_row_codec.dart';

void main() {
  test('ingredient companion carries scope + payload, round-trips', () {
    final item = Ingredient(
      id: 'a', name: '牛奶', quantity: '1', unit: '盒', imageUrl: '',
      freshnessPercent: 1, state: FreshnessState.fresh,
      storage: IconType.fridge, expiryDate: DateTime.utc(2026, 6, 1),
      remoteVersion: 2,
    );
    final c = inventoryCompanionFor('h1', item);
    expect(c.id.value, 'a');
    expect(c.householdId.value, 'h1');
    expect(c.remoteVersion.value, 2);
    expect(c.expiryDate.value, DateTime.utc(2026, 6, 1).millisecondsSinceEpoch);

    final back = ingredientFromPayload(c.payloadJson.value);
    // Ingredient has no value-equality override, so compare the canonical
    // JSON form to assert round-trip fidelity through the codec.
    expect(back.toJson(), item.toJson());
  });
}
