import '../data/recipe_presets.dart';
import '../models/recipe_draft.dart';

class RecipeDraftApplyResult {
  const RecipeDraftApplyResult({
    required this.name,
    required this.category,
    required this.cookingMinutes,
    required this.difficulty,
    required this.description,
    required this.coverImageSource,
    required this.ingredients,
    required this.steps,
  });

  final String name;
  final String category;
  final String cookingMinutes;
  final String difficulty;
  final String description;
  final String? coverImageSource;
  final List<AppliedIngredientRow> ingredients;
  final List<String> steps;
}

class AppliedIngredientRow {
  const AppliedIngredientRow({
    required this.name,
    required this.quantity,
    required this.unit,
  });

  final String name;
  final String quantity;
  final String unit;
}

// Matches a leading quantity token that may be:
//   - a fraction:  1/2
//   - a range:     2-3
//   - a decimal:   1.5
//   - an integer:  2
// followed by an optional remainder (the unit portion).
final _quantityRe = RegExp(r'^(\d+(?:[./\-]\d+)?)\s*(.*)$');

AppliedIngredientRow appliedIngredientRowFromDraft(RecipeIngredientDraft draft) {
  final amount = draft.amount.value.trim();
  final name = draft.name.value;

  if (amount.isEmpty) {
    return AppliedIngredientRow(name: name, quantity: '', unit: '');
  }

  final match = _quantityRe.firstMatch(amount);
  if (match != null) {
    final qty = match.group(1) ?? '';
    final remainder = (match.group(2) ?? '').trim();
    // Only accept remainder as unit if it's in the known units list.
    final unit = RecipePresets.units.contains(remainder) ? remainder : '';
    // If remainder is not a known unit, fold it into quantity text so we
    // don't produce junk like unit='/2个' or unit='-3根'.
    final quantityText = unit.isEmpty && remainder.isNotEmpty
        ? '$qty$remainder'
        : qty;
    return AppliedIngredientRow(name: name, quantity: quantityText, unit: unit);
  }

  // Descriptive amounts like "少许" have no numeric prefix — keep as quantity text.
  return AppliedIngredientRow(name: name, quantity: amount, unit: '');
}

RecipeDraftApplyResult recipeDraftToApplyResult(
  RecipeDraft draft, {
  required bool Function(String imageSource) isSupportedImageSource,
}) {
  final imageUrl = draft.imageUrl.value?.trim();
  final coverImageSource =
      imageUrl != null &&
              imageUrl.isNotEmpty &&
              isSupportedImageSource(imageUrl)
          ? imageUrl
          : null;

  return RecipeDraftApplyResult(
    name: draft.name.value,
    category: draft.category.value,
    cookingMinutes: draft.cookingMinutes.value.toString(),
    difficulty: draft.difficulty.value.toString(),
    description: draft.description.value,
    coverImageSource: coverImageSource,
    ingredients: draft.ingredients.map(appliedIngredientRowFromDraft).toList(),
    steps: draft.steps.map((step) => step.value).toList(),
  );
}
