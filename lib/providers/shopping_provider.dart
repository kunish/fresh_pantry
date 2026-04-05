import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shopping_item.dart';
import '../data/mock_data.dart';
import 'storage_service_provider.dart';

const _kShoppingKey = 'shopping_items';

/// Shopping list state with local persistence
class ShoppingNotifier extends Notifier<List<ShoppingItem>> {
  late final SharedPreferences _prefs;

  @override
  List<ShoppingItem> build() {
    _prefs = ref.read(sharedPreferencesProvider);
    return _load();
  }

  List<ShoppingItem> _load() {
    final jsonString = _prefs.getString(_kShoppingKey);
    if (jsonString == null) {
      return List.from(MockData.shoppingItems);
    }
    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((e) => ShoppingItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return List.from(MockData.shoppingItems);
    }
  }

  void _save() {
    final jsonString = json.encode(state.map((e) => e.toJson()).toList());
    _prefs.setString(_kShoppingKey, jsonString);
  }

  void add(ShoppingItem item) {
    state = [...state, item];
    _save();
  }

  void remove(String id) {
    state = state.where((item) => item.id != id).toList();
    _save();
  }

  void toggleCheck(String id) {
    state = state.map((item) {
      if (item.id == id) {
        return item.copyWith(isChecked: !item.isChecked);
      }
      return item;
    }).toList();
    _save();
  }

  void addFromSuggestion(String name) {
    final newItem = ShoppingItem(
      id: 'si_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      detail: '',
      category: '其他',
    );
    state = [...state, newItem];
    _save();
  }
}

final shoppingProvider = NotifierProvider<ShoppingNotifier, List<ShoppingItem>>(
  ShoppingNotifier.new,
);

/// Shopping items grouped by category
final groupedShoppingProvider = Provider<Map<String, List<ShoppingItem>>>((
  ref,
) {
  final items = ref.watch(shoppingProvider);
  final grouped = <String, List<ShoppingItem>>{};
  for (final item in items) {
    grouped.putIfAbsent(item.category, () => []).add(item);
  }
  return grouped;
});

/// Count of checked items
final checkedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => item.isChecked).length;
});

/// Count of unchecked items
final uncheckedCountProvider = Provider<int>((ref) {
  final items = ref.watch(shoppingProvider);
  return items.where((item) => !item.isChecked).length;
});
