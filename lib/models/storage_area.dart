enum IconType { fridge, pantry, freezer }

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
}
