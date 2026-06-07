import 'dart:convert';

import 'storage_adapter.dart';

/// Persists the set of avoided-ingredient keywords (忌口/dietary exclusions) as a
/// JSON string array.
///
/// Mirrors [FavoriteRecipesRepo]: a thin, defensive wrapper over a
/// [StorageAdapter]. A missing or malformed blob yields an empty set rather than
/// throwing. Keywords are stored as-is; normalization (trim + lowercase) is owned
/// by the notifier so the stored form stays the single source.
class DietaryPreferencesRepo {
  static const storageKey = 'dietary_exclusions';

  final StorageAdapter _adapter;

  DietaryPreferencesRepo(this._adapter);

  Set<String> load() {
    final raw = _adapter.read(storageKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().where((k) => k.isNotEmpty).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  void save(Set<String> keywords) {
    _adapter.write(storageKey, jsonEncode(keywords.toList()));
  }
}
