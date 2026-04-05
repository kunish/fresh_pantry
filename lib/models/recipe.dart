class RecipeIngredient {
  final String name;
  final String amount;

  const RecipeIngredient({required this.name, required this.amount});

  factory RecipeIngredient.fromJson(Map<String, dynamic> json) {
    return RecipeIngredient(
      name: json['name'] as String,
      amount: json['amount'] as String,
    );
  }
}

class Recipe {
  final String id;
  final String name;
  final String category;
  final int difficulty;
  final int cookingMinutes;
  final String description;
  final List<RecipeIngredient> ingredients;
  final List<String> steps;
  final List<String> tags;

  const Recipe({
    required this.id,
    required this.name,
    required this.category,
    required this.difficulty,
    required this.cookingMinutes,
    required this.description,
    required this.ingredients,
    required this.steps,
    this.tags = const [],
  });

  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      name: json['name'] as String,
      category: json['category'] as String? ?? '',
      difficulty: json['difficulty'] as int? ?? 0,
      cookingMinutes: json['cookingMinutes'] as int,
      description: json['description'] as String,
      ingredients: (json['ingredients'] as List<dynamic>)
          .map((e) => RecipeIngredient.fromJson(e as Map<String, dynamic>))
          .toList(),
      steps: (json['steps'] as List<dynamic>).cast<String>(),
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const [],
    );
  }
}

class ScoredRecipe {
  final Recipe recipe;
  final double score;
  final int matchedCount;
  final int expiringMatchedCount;

  const ScoredRecipe({
    required this.recipe,
    required this.score,
    required this.matchedCount,
    required this.expiringMatchedCount,
  });
}
