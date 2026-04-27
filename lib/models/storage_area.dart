enum IconType { fridge, pantry }

IconType iconTypeFromName(String? name) {
  return switch (name) {
    'pantry' => IconType.pantry,
    'fridge' || 'freezer' || null => IconType.fridge,
    _ => IconType.fridge,
  };
}

class StorageArea {
  final String name;
  final IconType icon;
  final int itemCount;
  final double capacityPercent;

  const StorageArea({
    required this.name,
    required this.icon,
    required this.itemCount,
    required this.capacityPercent,
  });

  StorageArea copyWith({
    String? name,
    IconType? icon,
    int? itemCount,
    double? capacityPercent,
  }) {
    return StorageArea(
      name: name ?? this.name,
      icon: icon ?? this.icon,
      itemCount: itemCount ?? this.itemCount,
      capacityPercent: capacityPercent ?? this.capacityPercent,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'icon': icon.name,
      'itemCount': itemCount,
      'capacityPercent': capacityPercent,
    };
  }

  factory StorageArea.fromJson(Map<String, dynamic> json) {
    return StorageArea(
      name: json['name'] as String? ?? '',
      icon: iconTypeFromName(json['icon'] as String?),
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      capacityPercent: (json['capacityPercent'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
