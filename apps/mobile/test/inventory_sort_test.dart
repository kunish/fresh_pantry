import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';

Ingredient _ing(String name, {DateTime? expiry}) => Ingredient(
  name: name,
  quantity: '1',
  unit: '份',
  imageUrl: '',
  freshnessPercent: 1,
  state: FreshnessState.fresh,
  expiryDate: expiry,
);

List<String> _names(List<Ingredient> items) =>
    items.map((i) => i.name).toList();

void main() {
  group('sortedInventoryItems', () {
    test('manual keeps the original insertion order untouched', () {
      final items = [
        _ing('番茄', expiry: DateTime(2026, 6, 20)),
        _ing('牛奶', expiry: DateTime(2026, 6, 8)),
        _ing('盐'),
      ];
      final sorted = sortedInventoryItems(items, InventorySortMode.manual);
      expect(_names(sorted), ['番茄', '牛奶', '盐']);
      // Manual is a no-op: it should hand back the very same list instance so
      // callers pay nothing when no ordering is requested.
      expect(identical(sorted, items), isTrue);
    });

    test('expiry orders soonest-to-expire first', () {
      final items = [
        _ing('番茄', expiry: DateTime(2026, 6, 20)),
        _ing('牛奶', expiry: DateTime(2026, 6, 8)),
        _ing('鸡蛋', expiry: DateTime(2026, 6, 14)),
      ];
      final sorted = sortedInventoryItems(items, InventorySortMode.expiry);
      expect(_names(sorted), ['牛奶', '鸡蛋', '番茄']);
    });

    test('expiry sinks items without an expiry date to the bottom', () {
      final items = [
        _ing('盐'),
        _ing('牛奶', expiry: DateTime(2026, 6, 8)),
        _ing('糖'),
        _ing('番茄', expiry: DateTime(2026, 6, 20)),
      ];
      final sorted = sortedInventoryItems(items, InventorySortMode.expiry);
      expect(_names(sorted), ['牛奶', '番茄', '盐', '糖']);
    });

    test('expiry breaks ties by original position (stable order)', () {
      final day = DateTime(2026, 6, 10);
      final items = [
        _ing('A', expiry: day),
        _ing('B', expiry: day),
        _ing('C', expiry: day),
      ];
      final sorted = sortedInventoryItems(items, InventorySortMode.expiry);
      expect(_names(sorted), ['A', 'B', 'C']);
    });

    test('expiry keeps insertion order when no item has an expiry date', () {
      final items = [_ing('盐'), _ing('糖'), _ing('米')];
      final sorted = sortedInventoryItems(items, InventorySortMode.expiry);
      expect(_names(sorted), ['盐', '糖', '米']);
    });

    test('handles the empty list', () {
      expect(sortedInventoryItems([], InventorySortMode.expiry), isEmpty);
      expect(sortedInventoryItems([], InventorySortMode.manual), isEmpty);
    });
  });
}
