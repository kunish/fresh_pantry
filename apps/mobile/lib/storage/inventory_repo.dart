import 'dart:convert';
import '../models/ingredient.dart';
import '../utils/ingredient_normalizer.dart';
import 'storage_adapter.dart';

class InventoryRepo {
  static const _inventoryKey = 'inventory_items';
  static const _addHistoryKey = 'add_history';

  final StorageAdapter _adapter;
  List<Ingredient>? _hydratedSeed;

  InventoryRepo(this._adapter);

  void hydrate(List<Ingredient> seed) {
    _hydratedSeed = seed;
  }

  List<Ingredient> loadAll() {
    if (_hydratedSeed != null) {
      final result = _hydratedSeed!;
      _hydratedSeed = null;
      return result;
    }
    final jsonStr = _adapter.read(_inventoryKey);
    if (jsonStr == null) return [];

    final decoded = _decodeListOrNull(jsonStr);
    // Top-level blob present but not a list: salvage nothing rather than let an
    // empty result auto-overwrite the still-intact stored JSON.
    if (decoded == null) return [];

    // Parse item-by-item: skip only individual bad entries, keep the rest.
    final items = <Ingredient>[];
    for (final entry in decoded) {
      if (entry is! Map) continue;
      try {
        items.add(
          normalizeInventoryIngredient(
            Ingredient.fromJson(Map<String, dynamic>.from(entry)),
          ),
        );
      } catch (_) {
        // Skip this malformed entry only; keep already-parsed items.
      }
    }
    return items;
  }

  List<dynamic>? _decodeListOrNull(String source) {
    try {
      final decoded = json.decode(source);
      return decoded is List ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  void saveItems(List<Ingredient> items) {
    final jsonStr = json.encode(items.map((e) => e.toJson()).toList());
    _adapter.write(_inventoryKey, jsonStr);
  }

  Map<String, dynamic> loadHistory() {
    final jsonStr = _adapter.read(_addHistoryKey);
    if (jsonStr == null) return {};
    try {
      return json.decode(jsonStr) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  void saveHistory(Map<String, dynamic> history) {
    _adapter.write(_addHistoryKey, json.encode(history));
  }

  void clearHistory() {
    _adapter.write(_addHistoryKey, json.encode(<String, dynamic>{}));
  }
}
