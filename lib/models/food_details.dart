import 'storage_area.dart';

class FoodDetails {
  final String displayName;
  final String description;
  final String? imageUrl;
  final String category;
  final IconType storage;
  final int? shelfLifeDays;
  final String source;
  final DateTime fetchedAt;

  const FoodDetails({
    required this.displayName,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.storage,
    required this.shelfLifeDays,
    required this.source,
    required this.fetchedAt,
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
      'cacheVersion': 4,
    };
  }

  factory FoodDetails.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
