import 'dart:convert';
import '../models/shopping_item.dart';
import 'shopping_item_normalizer.dart';
import 'storage_adapter.dart';

class ShoppingRepo {
  static const _shoppingKey = 'shopping_items';

  final StorageAdapter _adapter;
  List<ShoppingItem>? _hydratedSeed;

  ShoppingRepo(this._adapter);

  void hydrate(List<ShoppingItem> seed) {
    _hydratedSeed = seed;
  }

  List<ShoppingItem> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final json = _adapter.read(_shoppingKey);
    if (json == null) return [];

    final decoded = _decodeListOrNull(json);
    // Top-level blob present but not a list: salvage nothing, but signal
    // failure so an empty result never auto-overwrites the good blob.
    if (decoded == null) return [];

    // Parse item-by-item: skip only individual bad entries, keep the rest.
    final items = <ShoppingItem>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        items.add(
          normalizeShoppingItemCategory(
            ShoppingItem.fromJson(Map<String, dynamic>.from(entry)),
          ),
        );
      } catch (_) {
        // Skip this malformed entry only; keep already-parsed items.
      }
    }
    return deduplicateShoppingItems(items);
  }

  List<dynamic>? _decodeListOrNull(String source) {
    try {
      final decoded = json.decode(source);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void saveItems(List<ShoppingItem> items) {
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    _adapter.write(_shoppingKey, jsonStr);
  }
}
