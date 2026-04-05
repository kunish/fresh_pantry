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
  });

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
    };
  }

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    return Ingredient(
      name: json['name'] as String,
      quantity: json['quantity'] as String,
      unit: json['unit'] as String,
      imageUrl: json['imageUrl'] as String,
      freshnessPercent: (json['freshnessPercent'] as num).toDouble(),
      state: FreshnessState.values.byName(json['state'] as String),
      expiryLabel: json['expiryLabel'] as String?,
      category: json['category'] as String?,
      barcode: json['barcode'] as String?,
    );
  }
}
