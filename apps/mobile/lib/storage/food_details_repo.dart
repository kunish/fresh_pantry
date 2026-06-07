import 'dart:convert';

import '../data/food_categories.dart';
import '../data/food_knowledge.dart';
import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../models/storage_area.dart';
import '../services/food_details_client.dart';
import '../utils/normalize_cache_key.dart';
import '../utils/storage_labels.dart';
import 'storage_adapter.dart';

const foodDetailsCacheStorageKey = 'food_details_cache';
const _localFoodDetailsSource = '本地食材知识库';
// Bump in lockstep with FoodDetails.toJson's 'cacheVersion' — v5 added
// nutrition, so v4 caches are stale and get re-fetched with macros.
const _foodDetailsCacheVersion = 5;

String foodDetailsCacheKeyFor(Ingredient ingredient) {
  final barcode = ingredient.barcode?.trim();
  if (barcode != null && barcode.isNotEmpty) return 'barcode:$barcode';
  return 'name:${normalizeCacheKey(ingredient.name)}';
}

class FoodDetailsRepository {
  FoodDetailsRepository({required this.storage, required this.client});

  final StorageAdapter storage;
  final FoodDetailsClient client;
  String? _cachedRawCache;
  Map<String, dynamic>? _cachedDecodedCache;

  Future<FoodDetails> detailsFor(Ingredient ingredient) async {
    final cache = _readCache();
    final key = foodDetailsCacheKeyFor(ingredient);
    final cachedValue = cache[key];
    final cachedDetails = _cachedDetailsFrom(cachedValue);
    if (cachedDetails != null &&
        _isCurrentCacheValue(cachedValue) &&
        !_isLocalFallback(cachedDetails)) {
      return cachedDetails;
    }

    FoodDetails? fetched;
    try {
      fetched = await client.lookup(ingredient);
    } catch (_) {
      fetched = null;
    }

    final details =
        fetched ?? cachedDetails ?? fallbackFoodDetailsFor(ingredient);
    // Only persist real/online details. A local fallback (offline/failed
    // lookup) is not worth a full cache-map rewrite on every read, and
    // caching it would mask the missing online data on the next lookup.
    if (_isLocalFallback(details)) {
      return details;
    }
    cache[key] = details.toJson();
    final encoded = jsonEncode(cache);
    await storage.write(foodDetailsCacheStorageKey, encoded);
    _cachedRawCache = encoded;
    _cachedDecodedCache = Map<String, dynamic>.from(cache);
    return details;
  }

  FoodDetails? _cachedDetailsFrom(Object? value) {
    if (value is Map<String, dynamic>) {
      return FoodDetails.fromJson(value);
    }
    if (value is Map) {
      return FoodDetails.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  bool _isLocalFallback(FoodDetails details) {
    return details.source == _localFoodDetailsSource;
  }

  bool _isCurrentCacheValue(Object? value) {
    if (value is Map<String, dynamic>) {
      return value['cacheVersion'] == _foodDetailsCacheVersion;
    }
    if (value is Map) {
      return value['cacheVersion'] == _foodDetailsCacheVersion;
    }
    return false;
  }

  Map<String, dynamic> _readCache() {
    final raw = storage.read(foodDetailsCacheStorageKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    if (raw == _cachedRawCache && _cachedDecodedCache != null) {
      return Map<String, dynamic>.from(_cachedDecodedCache!);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final cache = Map<String, dynamic>.from(decoded);
        _cachedRawCache = raw;
        _cachedDecodedCache = Map<String, dynamic>.from(cache);
        return cache;
      }
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
}

FoodDetails fallbackFoodDetailsFor(Ingredient ingredient, {DateTime? now}) {
  final defaults = FoodKnowledge.lookup(ingredient.name);
  final category = FoodCategories.dropdownValue(
    defaults?.category ?? ingredient.category,
  );
  final storage = defaults?.storage ?? ingredient.storage;
  final shelfLifeDays = defaults?.shelfLifeDays ?? ingredient.shelfLifeDays;
  final imageUrl = _fallbackImageUrl(ingredient);

  return FoodDetails(
    displayName: ingredient.name,
    description: _fallbackDescription(storage, shelfLifeDays),
    imageUrl: imageUrl,
    category: category,
    storage: storage,
    shelfLifeDays: shelfLifeDays,
    source: _localFoodDetailsSource,
    fetchedAt: now ?? DateTime.now(),
  );
}

String _fallbackDescription(IconType storage, int? shelfLifeDays) {
  final storageLabel = storageLabelFor(storage);
  if (shelfLifeDays != null && shelfLifeDays > 0) {
    return '建议存放在$storageLabel，约 $shelfLifeDays 天内食用。';
  }
  return '暂无联网详情，已保留本地库存中的食材信息。';
}

/// Whether [description] is a system-generated placeholder rather than a real
/// food description (so presentation can hide it).
///
/// This is the single authority for "is this a placeholder?". It mirrors the
/// templates minted by [_fallbackDescription] above and the Open Food Facts
/// generic line in `open_food_facts_service.dart`
/// (`'Open Food Facts 记录的$category食品。'`) — keep these three checks in sync
/// with those producers if a template ever changes.
bool isPlaceholderFoodDescription(String description) {
  final trimmed = description.trim();
  if (trimmed.isEmpty) return true;
  if (trimmed.startsWith('Open Food Facts 记录的') && trimmed.endsWith('食品。')) {
    return true;
  }
  if (trimmed.startsWith('建议存放在')) return true;
  if (trimmed.startsWith('暂无联网详情')) return true;
  return false;
}

String? _fallbackImageUrl(Ingredient ingredient) {
  final savedImage = ingredient.imageUrl.trim();
  if (savedImage.isNotEmpty) return savedImage;

  final englishName = FoodKnowledge.englishName(ingredient.name);
  if (englishName == null || englishName.trim().isEmpty) return null;

  final slug = englishName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  return 'https://www.themealdb.com/images/ingredients/$slug.png';
}
