class ShoppingItem {
  final String id;
  final String name;
  final String detail;
  final String? imageUrl;
  final String category;
  final bool isChecked;

  const ShoppingItem({
    required this.id,
    required this.name,
    required this.detail,
    this.imageUrl,
    required this.category,
    this.isChecked = false,
  });

  ShoppingItem copyWith({
    String? id,
    String? name,
    String? detail,
    String? imageUrl,
    String? category,
    bool? isChecked,
  }) {
    return ShoppingItem(
      id: id ?? this.id,
      name: name ?? this.name,
      detail: detail ?? this.detail,
      imageUrl: imageUrl ?? this.imageUrl,
      category: category ?? this.category,
      isChecked: isChecked ?? this.isChecked,
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
    };
  }

  factory ShoppingItem.fromJson(Map<String, dynamic> json) {
    return ShoppingItem(
      id: json['id'] as String,
      name: json['name'] as String,
      detail: json['detail'] as String,
      imageUrl: json['imageUrl'] as String?,
      category: json['category'] as String,
      isChecked: json['isChecked'] as bool? ?? false,
    );
  }
}
