import '../data/food_categories.dart';
import 'ingredient.dart';
import 'sync_metadata.dart';

class ShoppingItem {
  final String id;
  final String name;
  final String detail;
  final String? imageUrl;
  final String category;
  final bool isChecked;
  final int remoteVersion;
  final DateTime? clientUpdatedAt;
  final DateTime? deletedAt;

  SyncMetadata get syncMetadata => SyncMetadata(
    remoteVersion: remoteVersion,
    clientUpdatedAt: clientUpdatedAt,
    deletedAt: deletedAt,
  );

  const ShoppingItem({
    required this.id,
    required this.name,
    required this.detail,
    this.imageUrl,
    required this.category,
    this.isChecked = false,
    this.remoteVersion = 0,
    this.clientUpdatedAt,
    this.deletedAt,
  });

  /// Generate a fresh shopping item id with the canonical `si_<ms>` format.
  static String newId() => 'si_${DateTime.now().millisecondsSinceEpoch}';

  /// Build a ShoppingItem from an Ingredient. Uses `id` if provided,
  /// otherwise generates a fresh one. Mirrors the existing `_shoppingItemFor`
  /// implementations in dashboard/inventory/ingredient_detail screens.
  factory ShoppingItem.fromIngredient(Ingredient ingredient, {String? id}) {
    return ShoppingItem(
      id: id ?? ShoppingItem.newId(),
      name: ingredient.name,
      detail: '${ingredient.quantity} ${ingredient.unit}',
      imageUrl: ingredient.imageUrl.isEmpty ? null : ingredient.imageUrl,
      category: ingredient.category ?? FoodCategories.other,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShoppingItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  ShoppingItem copyWith({
    String? id,
    String? name,
    String? detail,
    String? imageUrl,
    String? category,
    bool? isChecked,
    int? remoteVersion,
    DateTime? clientUpdatedAt,
    DateTime? deletedAt,
    bool clearClientUpdatedAt = false,
    bool clearDeletedAt = false,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isChecked: isChecked ?? this.isChecked,
      remoteVersion: remoteVersion ?? this.remoteVersion,
      clientUpdatedAt: clearClientUpdatedAt
          ? null
          : clientUpdatedAt ?? this.clientUpdatedAt,
      deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'detail': detail,
      'imageUrl': imageUrl,
      'category': category,
      'isChecked': isChecked,
      'remoteVersion': remoteVersion,
      'clientUpdatedAt': dateTimeToJsonValue(clientUpdatedAt),
      'deletedAt': dateTimeToJsonValue(deletedAt),
    };
  }

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String? ?? FoodCategories.other,
      isChecked: json['isChecked'] as bool? ?? false,
      remoteVersion: (json['remoteVersion'] as num?)?.toInt() ?? 0,
      clientUpdatedAt: dateTimeFromJsonValue(json['clientUpdatedAt']),
      deletedAt: dateTimeFromJsonValue(json['deletedAt']),
    );
  }
}
