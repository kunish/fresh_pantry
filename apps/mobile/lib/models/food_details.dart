import 'storage_area.dart';

/// Per-100g macro nutrition facts, sourced from Open Food Facts.
///
/// Every field is nullable: a product may report only some macros (or none).
/// [hasAny] gates whether the UI shows a nutrition card at all.
class NutritionFacts {
  final double? energyKcal; // kcal / 100g
  final double? protein; // g / 100g
  final double? carbs; // g / 100g
  final double? fat; // g / 100g

  const NutritionFacts({this.energyKcal, this.protein, this.carbs, this.fat});

  bool get hasAny =>
      energyKcal != null || protein != null || carbs != null || fat != null;

  Map<String, dynamic> toJson() => {
    'energyKcal': energyKcal,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
  };

  factory NutritionFacts.fromJson(Map<String, dynamic> json) => NutritionFacts(
    energyKcal: _toDouble(json['energyKcal']),
    protein: _toDouble(json['protein']),
    carbs: _toDouble(json['carbs']),
    fat: _toDouble(json['fat']),
  );

  /// Build from an Open Food Facts `nutriments` map (per-100g keys). Returns
  /// null when no usable macro is present, so callers don't store empty facts.
  static NutritionFacts? fromOffNutriments(Map<String, dynamic> n) {
    final facts = NutritionFacts(
      energyKcal: _toDouble(n['energy-kcal_100g']),
      protein: _toDouble(n['proteins_100g']),
      carbs: _toDouble(n['carbohydrates_100g']),
      fat: _toDouble(n['fat_100g']),
    );
    return facts.hasAny ? facts : null;
  }

  static double? _toDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NutritionFacts &&
          runtimeType == other.runtimeType &&
          energyKcal == other.energyKcal &&
          protein == other.protein &&
          carbs == other.carbs &&
          fat == other.fat;

  @override
  int get hashCode => Object.hash(energyKcal, protein, carbs, fat);
}

class FoodDetails {
  final String displayName;
  final String description;
  final String? imageUrl;
  final String category;
  final IconType storage;
  final int? shelfLifeDays;
  final String source;
  final DateTime fetchedAt;
  final NutritionFacts? nutrition;

  const FoodDetails({
    required this.displayName,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    required this.source,
    required this.fetchedAt,
    this.nutrition,
  });

  Map<String, dynamic> toJson() {
    return {
      'displayName': displayName,
      'description': description,
      'imageUrl': imageUrl,
      'category': category,
      'storage': storage.name,
      'shelfLifeDays': shelfLifeDays,
      'source': source,
      'fetchedAt': fetchedAt.toIso8601String(),
      'nutrition': nutrition?.toJson(),
      // Bump in lockstep with `_foodDetailsCacheVersion` in
      // food_details_repo.dart — older caches (v4, pre-nutrition) are then
      // treated as stale and re-fetched with nutrition.
      'cacheVersion': 5,
    };
  }

  factory FoodDetails.fromJson(Map<String, dynamic> json) {
    final nutritionJson = json['nutrition'];
    return FoodDetails(
      displayName: json['displayName'] as String? ?? '',
      description: json['description'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String? ?? '',
      storage: iconTypeFromName(json['storage'] as String?),
      shelfLifeDays: (json['shelfLifeDays'] as num?)?.toInt(),
      source: json['source'] as String? ?? '',
      fetchedAt:
          json['fetchedAt'] is String
              ? DateTime.tryParse(json['fetchedAt'] as String) ??
                  DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
              : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      nutrition: nutritionJson is Map
          ? NutritionFacts.fromJson(Map<String, dynamic>.from(nutritionJson))
          : null,
    );
  }
}
