import 'storage_area.dart';

/// A frequently added item with remembered defaults.
class FrequentItem {
  final String name;
  final String category;
  final IconType storage;
  final String unit;
  final int? shelfLifeDays;
  final int count;

  const FrequentItem({
    required this.name,
    required this.category,
    required this.storage,
    required this.unit,
    this.shelfLifeDays,
    required this.count,
  });

  // Value equality so the derived List<FrequentItem> exposed by
  // frequentItemsProvider / lowStockItemsProvider compares by content. The list
  // is rebuilt from scratch on every history change, so without this each
  // rebuild yields identity-unequal instances and re-emits to watchers even
  // when nothing changed.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FrequentItem &&
          runtimeType == other.runtimeType &&
          name == other.name &&
          category == other.category &&
          storage == other.storage &&
          unit == other.unit &&
          shelfLifeDays == other.shelfLifeDays &&
          count == other.count;

  @override
  int get hashCode =>
      Object.hash(name, category, storage, unit, shelfLifeDays, count);
}
