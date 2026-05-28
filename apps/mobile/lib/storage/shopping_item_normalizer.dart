import '../data/food_categories.dart';
import '../models/shopping_item.dart';

/// Shared shopping-item normalization, identity, and de-duplication helpers.
///
/// Centralized so the repo (load/save) and the provider (in-memory mutations,
/// `replaceFromRemote`) share a single source of truth. Previously these were
/// copy-pasted in both files and dedup logic diverged (the repo deduped by name
/// on load while the provider did not dedup at all), letting in-memory and
/// reloaded lists drift apart.

/// Canonical category fallback for a shopping item.
ShoppingItem normalizeShoppingItemCategory(ShoppingItem item) {
  final category =
      FoodCategories.normalize(item.category) ?? FoodCategories.other;
  if (category == item.category) return item;
  return item.copyWith(category: category);
}

/// Full normalization: canonical category plus trimmed name/detail.
ShoppingItem normalizeShoppingItem(ShoppingItem item) {
  final normalizedCategory = normalizeShoppingItemCategory(item);
  final trimmedName = normalizedCategory.name.trim();
  final trimmedDetail = normalizedCategory.detail.trim();
  if (trimmedName == normalizedCategory.name &&
      trimmedDetail == normalizedCategory.detail) {
    return normalizedCategory;
  }
  return normalizedCategory.copyWith(name: trimmedName, detail: trimmedDetail);
}

/// Case-insensitive name key, used for duplicate-name guards on user input.
String shoppingItemNameKey(String name) => name.trim().toLowerCase();

/// Returns [item] with an id guaranteed unique within [existingIds],
/// minting a fresh id for blank ids and suffixing collisions.
ShoppingItem withUniqueShoppingItemId(
  ShoppingItem item,
  Set<String> existingIds,
) {
  final trimmedId = item.id.trim();
  final baseId = trimmedId.isEmpty ? ShoppingItem.newId() : trimmedId;
  var candidateId = baseId;
  var suffix = 2;

  while (existingIds.contains(candidateId)) {
    candidateId = '${baseId}_$suffix';
    suffix += 1;
  }

  existingIds.add(candidateId);
  return candidateId == item.id ? item : item.copyWith(id: candidateId);
}

/// De-duplicates by case-insensitive name — the shopping list's user-facing
/// identity, which `add` already enforces — keeping the first occurrence and
/// dropping blank-name rows. Survivors are given unique ids defensively.
/// Applied on load AND in `replaceFromRemote` so the in-memory and reloaded
/// lists cannot diverge (the bug was the repo deduping on load while the
/// provider did not).
List<ShoppingItem> deduplicateShoppingItems(Iterable<ShoppingItem> items) {
  final seenNames = <String>{};
  final seenIds = <String>{};
  final deduplicated = <ShoppingItem>[];

  for (final item in items) {
    final nameKey = shoppingItemNameKey(item.name);
    if (nameKey.isEmpty || seenNames.contains(nameKey)) continue;
    seenNames.add(nameKey);
    deduplicated.add(withUniqueShoppingItemId(item, seenIds));
  }

  return deduplicated;
}
