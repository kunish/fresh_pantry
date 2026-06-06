// lib/utils/food_details_summary.dart
//
// Presentation formatting for a [FoodDetails] subtitle line, extracted from the
// search overlay so the rule is testable without pumping a widget. Placeholder
// detection is delegated to the data layer (`isPlaceholderFoodDescription`) so
// this file never re-hardcodes the producer templates.

import '../models/food_details.dart';
import '../storage/food_details_repo.dart';
import 'storage_labels.dart';

/// Composes the one-line "desc · category · 保存 · 约 N 天" summary shown under a
/// food-details search result. A placeholder description is omitted; if nothing
/// useful remains, a generic "查看食材详情" fallback is returned.
String foodDetailsSummary(FoodDetails details) {
  final parts = <String>[];

  final description = details.description.trim();
  if (!isPlaceholderFoodDescription(description)) {
    parts.add(description);
  }

  final category = details.category.trim();
  if (category.isNotEmpty) {
    parts.add(category);
  }

  parts.add('${storageLabelFor(details.storage)}保存');

  final shelfLifeDays = details.shelfLifeDays;
  if (shelfLifeDays != null && shelfLifeDays > 0) {
    parts.add('约 $shelfLifeDays 天');
  }

  return parts.isEmpty ? '查看食材详情' : parts.join(' · ');
}
