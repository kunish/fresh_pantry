import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/recipe.dart';
import '../models/ingredient.dart';
import '../data/mock_data.dart';
import '../services/themealdb_service.dart';
import 'inventory_provider.dart';

/// All available recipes — fetches from TheMealDB, falls back to mock data
final recipesProvider = FutureProvider<List<Recipe>>((ref) async {
  final inventory = ref.watch(inventoryProvider);
  if (inventory.isEmpty) return List.from(MockData.recipes);

  // Use first few inventory item names to search for relevant recipes
  final searchTerms = inventory
      .take(3)
      .map((i) => i.name)
      .toList();

  final allRecipes = <Recipe>[];
  final seenIds = <String>{};

  for (final term in searchTerms) {
    final results = await TheMealDbService.searchByName(term);
    for (final recipe in results) {
      if (seenIds.add(recipe.id)) {
        allRecipes.add(recipe);
      }
    }
  }

  // If API returned nothing, fall back to mock data
  if (allRecipes.isEmpty) return List.from(MockData.recipes);

  return allRecipes;
});

/// Recipes that can be made with current inventory ingredients
final recommendedRecipesProvider = Provider<List<Recipe>>((ref) {
  final recipesAsync = ref.watch(recipesProvider);
  final inventory = ref.watch(inventoryProvider);

  final recipes = recipesAsync.when(
    data: (data) => data,
    loading: () => List<Recipe>.from(MockData.recipes),
    error: (_, _) => List<Recipe>.from(MockData.recipes),
  );

  final inventoryNames = inventory.map((i) => i.name.toLowerCase()).toSet();

  // Score each recipe by how many ingredients are available
  final scored = recipes.map((recipe) {
    final matched = recipe.ingredients
        .where(
          (ing) => inventoryNames.any(
            (name) =>
                name.contains(ing.name.toLowerCase()) ||
                ing.name.toLowerCase().contains(name),
          ),
        )
        .length;
    return (recipe: recipe, score: matched / recipe.ingredients.length);
  }).toList();

  // Sort by match score descending
  scored.sort((a, b) => b.score.compareTo(a.score));
  return scored.map((e) => e.recipe).toList();
});

/// Count of matching inventory items for a recipe
int matchedIngredientCount(List<Ingredient> inventory, Recipe recipe) {
  final inventoryNames = inventory.map((i) => i.name.toLowerCase()).toSet();
  return recipe.ingredients
      .where(
        (ing) => inventoryNames.any(
          (name) =>
              name.contains(ing.name.toLowerCase()) ||
              ing.name.toLowerCase().contains(name),
        ),
      )
      .length;
}
