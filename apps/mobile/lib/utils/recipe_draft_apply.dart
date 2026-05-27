import '../models/recipe.dart';
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

AppliedIngredientRow appliedIngredientRowFromDraft(RecipeIngredientDraft draft) {
  final ingredient = RecipeIngredient.fromJson({
    'name': draft.name.value,
    'amount': draft.amount.value,
  });

  if (ingredient.quantity.isNotEmpty) {
    return AppliedIngredientRow(
      name: ingredient.name,
      quantity: ingredient.quantity,
      unit: ingredient.unit,
    );
  }

  // Descriptive amounts like "少许" have no numeric prefix — keep as quantity text.
  return AppliedIngredientRow(
    name: ingredient.name,
    quantity: ingredient.amount,
    unit: '',
  );
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
