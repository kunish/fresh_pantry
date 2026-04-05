import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart';
import '../data/mock_data.dart';
import 'storage_service_provider.dart';

const _kInventoryKey = 'inventory_items';

/// Inventory state (CRUD) with local persistence
class InventoryNotifier extends Notifier<List<Ingredient>> {
  late final SharedPreferences _prefs;

  @override
  List<Ingredient> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<Ingredient> _load() {
    final jsonString = _prefs.getString(_kInventoryKey);
    if (jsonString == null) {
      return List.from(MockData.inventoryItems);
    }
    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((e) => Ingredient.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return List.from(MockData.inventoryItems);
    }
  }

  void _save() {
    final jsonString = json.encode(state.map((e) => e.toJson()).toList());
    _prefs.setString(_kInventoryKey, jsonString);
  }

  void add(Ingredient item) {
    state = [...state, item];
    _save();
  }

  void remove(int index) {
    state = [...state]..removeAt(index);
    _save();
  }

  void update(int index, Ingredient item) {
    final updated = [...state];
    updated[index] = item;
    state = updated;
    _save();
  }

  List<Ingredient> getByCategory(String category) {
    if (category == '全部' || category.isEmpty) return state;
    return state.where((item) => item.category == category).toList();
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

/// Items expiring soon (state == expiringSoon or expired)
final expiringItemsProvider = Provider<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items
      .where(
        (item) =>
            item.state == FreshnessState.expiringSoon ||
            item.state == FreshnessState.expired,
      )
      .toList();
});

/// Recent additions (from mock data)
final recentAdditionsProvider = Provider<List<Ingredient>>((ref) {
  // In a real app, this would be sorted by date added
  // For now, use the dedicated mock data list
  return List.from(MockData.recentAdditions);
});

/// Stat counts for dashboard
final statCountsProvider = Provider<({int total, int expiringSoon})>((ref) {
  final items = ref.watch(inventoryProvider);
  final expiring = ref.watch(expiringItemsProvider);
  return (total: items.length, expiringSoon: expiring.length);
});

/// Available categories derived from inventory
final categoriesProvider = Provider<List<String>>((ref) {
  final items = ref.watch(inventoryProvider);
  final categories = <String>{'全部'};
  for (final item in items) {
    if (item.category != null && item.category!.isNotEmpty) {
      categories.add(item.category!);
    }
  }
  return categories.toList();
});

/// Currently selected category filter
final selectedCategoryProvider = StateProvider<String>((ref) => '全部');

/// Inventory filtered by selected category
final filteredByCategoryProvider = Provider<List<Ingredient>>((ref) {
  final category = ref.watch(selectedCategoryProvider);
  final items = ref.watch(inventoryProvider);
  if (category == '全部') return items;
  return items.where((item) => item.category == category).toList();
});
