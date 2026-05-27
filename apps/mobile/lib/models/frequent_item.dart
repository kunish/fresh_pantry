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
}
