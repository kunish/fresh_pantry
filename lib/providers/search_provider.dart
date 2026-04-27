import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'inventory_provider.dart';
import 'shopping_provider.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';

/// Current search keyword
final searchProvider = StateProvider<String>((ref) => '');

/// Filtered inventory based on search keyword
final filteredInventoryProvider = Provider<List<Ingredient>>((ref) {
  final keyword = ref.watch(searchProvider).trim().toLowerCase();
  final items = ref.watch(inventoryProvider);

  if (keyword.isEmpty) return items;

  return items.where((item) {
    return item.name.toLowerCase().contains(keyword) ||
        (item.category?.toLowerCase().contains(keyword) ?? false);
  }).toList();
});

/// Filtered shopping list based on search keyword
final filteredShoppingProvider = Provider<List<ShoppingItem>>((ref) {
  final keyword = ref.watch(searchProvider).trim().toLowerCase();
  final items = ref.watch(shoppingProvider);

  if (keyword.isEmpty) return items;

  return items.where((item) {
    return item.name.toLowerCase().contains(keyword) ||
        item.category.toLowerCase().contains(keyword);
  }).toList();
});

/// Search history — stores recent search terms (max 10)
class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => [];

  void add(String term) {
    final trimmed = term.trim();
    if (trimmed.isEmpty) return;
    // Remove if already exists, then add to front
    state = [trimmed, ...state.where((t) => t != trimmed)].take(10).toList();
  }

  void remove(String term) {
    state = state.where((t) => t != term).toList();
  }

  void clear() {
    state = [];
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(
      SearchHistoryNotifier.new,
    );
