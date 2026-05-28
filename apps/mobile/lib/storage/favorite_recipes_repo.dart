import 'dart:convert';

import 'storage_adapter.dart';

/// Persists the set of favorited recipe ids as a JSON string array.
///
/// Mirrors the seam used by [AiSettingsRepo] / [ShoppingRepo]: a thin wrapper
/// over a [StorageAdapter] that decodes defensively. A missing or malformed
/// blob yields an empty set rather than throwing.
class FavoriteRecipesRepo {
  static const storageKey = 'favorite_recipe_ids';

  final StorageAdapter _adapter;

  FavoriteRecipesRepo(this._adapter);

  Set<String> load() {
    final raw = _adapter.read(storageKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      // Keep only non-empty string ids; skip any malformed entries.
      return decoded.whereType<String>().where((id) => id.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  void save(Set<String> ids) {
    _adapter.write(storageKey, jsonEncode(ids.toList()));
  }
}
