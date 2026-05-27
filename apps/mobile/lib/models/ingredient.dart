import '../models/storage_area.dart';

enum FreshnessState { fresh, expiringSoon, expired }

class Ingredient {
  final String name;
  final String quantity;
  final String unit;
  final String imageUrl;
  final double freshnessPercent;
  final FreshnessState state;
  final String? expiryLabel;
  final String? category;
  final String? barcode;
  final IconType storage;
  final DateTime? expiryDate;
  final DateTime? addedAt;
  final int? shelfLifeDays;

  const Ingredient({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.imageUrl,
    required this.freshnessPercent,
    required this.state,
    this.expiryLabel,
    this.category,
    this.barcode,
    this.storage = IconType.fridge,
    this.expiryDate,
    this.addedAt,
    this.shelfLifeDays,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ingredient &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          quantity == other.quantity &&
          unit == other.unit &&
          imageUrl == other.imageUrl &&
          freshnessPercent == other.freshnessPercent &&
          state == other.state &&
          expiryLabel == other.expiryLabel &&
          category == other.category &&
          barcode == other.barcode &&
          storage == other.storage &&
          expiryDate == other.expiryDate &&
          addedAt == other.addedAt &&
          shelfLifeDays == other.shelfLifeDays;

  @override
  int get hashCode => Object.hash(
    name,
    quantity,
    unit,
    imageUrl,
    freshnessPercent,
    state,
    expiryLabel,
    category,
    barcode,
    storage,
    expiryDate,
    addedAt,
    shelfLifeDays,
  );

  Ingredient copyWith({
    String? name,
    String? quantity,
    String? unit,
    String? imageUrl,
    double? freshnessPercent,
    FreshnessState? state,
    String? expiryLabel,
    String? category,
    String? barcode,
    IconType? storage,
    DateTime? expiryDate,
    DateTime? addedAt,
    int? shelfLifeDays,
  }) {
    return Ingredient(
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      imageUrl: imageUrl ?? this.imageUrl,
      freshnessPercent: freshnessPercent ?? this.freshnessPercent,
      state: state ?? this.state,
      expiryLabel: expiryLabel ?? this.expiryLabel,
      category: category ?? this.category,
      barcode: barcode ?? this.barcode,
      storage: storage ?? this.storage,
      expiryDate: expiryDate ?? this.expiryDate,
      addedAt: addedAt ?? this.addedAt,
      shelfLifeDays: shelfLifeDays ?? this.shelfLifeDays,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'quantity': quantity,
      'unit': unit,
      'imageUrl': imageUrl,
      'freshnessPercent': freshnessPercent,
      'state': state.name,
      'expiryLabel': expiryLabel,
      'category': category,
      'barcode': barcode,
      'storage': storage.name,
      'expiryDate': expiryDate?.toIso8601String(),
      'addedAt': addedAt?.toIso8601String(),
      'shelfLifeDays': shelfLifeDays,
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    FreshnessState state;
    try {
      state = FreshnessState.values.byName(json['state'] as String? ?? 'fresh');
    } catch (_) {
      state = FreshnessState.fresh;
    }

    return Ingredient(
      name: json['name'] as String? ?? '',
      quantity: json['quantity'] as String? ?? '1',
      unit: json['unit'] as String? ?? '份',
      imageUrl: json['imageUrl'] as String? ?? '',
      freshnessPercent: (json['freshnessPercent'] as num?)?.toDouble() ?? 1.0,
      state: state,
      expiryLabel: json['expiryLabel'] as String?,
      category: json['category'] as String?,
      barcode: json['barcode'] as String?,
      storage: iconTypeFromName(json['storage'] as String?),
      expiryDate:
          json['expiryDate'] is String
              ? DateTime.tryParse(json['expiryDate'] as String)
              : null,
      addedAt:
          json['addedAt'] is String
              ? DateTime.tryParse(json['addedAt'] as String)
              : null,
      shelfLifeDays: (json['shelfLifeDays'] as num?)?.toInt(),
    );
  }
}
