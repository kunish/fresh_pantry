# Open API Data Enrichment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace hardcoded mock data with real data from open APIs (Open Food Facts for ingredients, TheMealDB for recipes) to enrich images, nutrition, and recipe content.

**Architecture:** Three new services wrap open APIs behind simple Dart interfaces. Each returns nullable results so callers gracefully fall back to existing defaults. The `BarcodeResult` model is extended to carry image URLs. A new `TheMealDbService` provides real recipes with images. Providers are updated to call services and cache results.

**Tech Stack:** Flutter/Dart, Riverpod, `http` package (already in pubspec), Open Food Facts API v2, TheMealDB API v1

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/services/open_food_facts_service.dart` | **Modify** — Extend `BarcodeResult` with `imageUrl`, add `searchByName()` for ingredient lookup |
| `lib/models/recipe.dart` | **Modify** — Add `imageUrl` field to `Recipe` |
| `lib/services/themealdb_service.dart` | **Create** — TheMealDB API client: search by name, lookup by ID, search by ingredient |
| `lib/providers/recipe_provider.dart` | **Modify** — Use TheMealDB for recipe data, keep mock as fallback |
| `lib/data/mock_data.dart` | **Modify** — Add `imageUrl` to mock recipes for offline fallback |
| `lib/screens/add_ingredient_screen.dart` | **Modify** — Call Open Food Facts search after name input to get image URL |
| `lib/screens/recipe_detail_screen.dart` | **Modify** — Display recipe image from URL |
| `lib/widgets/recipe_card.dart` | **Modify** — Display recipe thumbnail from URL |
| `lib/widgets/inventory/ingredient_card.dart` | No change needed — already handles `imageUrl` with error fallback |

---

### Task 1: Extend BarcodeResult with Image URL

**Files:**
- Modify: `lib/services/open_food_facts_service.dart`

- [ ] **Step 1: Add `imageUrl` field to `BarcodeResult`**

```dart
class BarcodeResult {
  final String productName;
  final String? category;
  final String barcode;
  final String? imageUrl;

  const BarcodeResult({
    required this.productName,
    required this.barcode,
    this.category,
    this.imageUrl,
  });
}
```

- [ ] **Step 2: Extract image URL from API response in `lookup()`**

In the `lookup` method, after extracting `name` and `category`, add:

```dart
final imageUrl = product['image_front_url'] as String? ??
    product['image_url'] as String?;
```

And pass it to the constructor:

```dart
return BarcodeResult(
  productName: name,
  barcode: barcode,
  category: category,
  imageUrl: imageUrl,
);
```

- [ ] **Step 3: Verify the change compiles**

Run: `flutter analyze lib/services/open_food_facts_service.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/services/open_food_facts_service.dart
git commit -m "feat: extract product image URL from Open Food Facts barcode lookup"
```

---

### Task 2: Add Name-Based Ingredient Search to Open Food Facts Service

**Files:**
- Modify: `lib/services/open_food_facts_service.dart`

- [ ] **Step 1: Add `searchByName()` static method**

This uses the Open Food Facts v2 search endpoint to find a product by name and return its image URL and category.

```dart
/// Search Open Food Facts by ingredient name. Returns the best match or null.
static Future<BarcodeResult?> searchByName(String name) async {
  try {
    final uri = Uri.parse(
      'https://world.openfoodfacts.org/cgi/search.pl'
      '?search_terms=${Uri.encodeComponent(name)}'
      '&search_simple=1&action=process&json=1&page_size=1'
      '&fields=product_name,categories_tags,image_front_small_url,code',
    );
    final response = await http.get(uri).timeout(_timeout);

    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final products = json['products'] as List<dynamic>?;
    if (products == null || products.isEmpty) return null;

    final product = products.first as Map<String, dynamic>;
    final productName = product['product_name'] as String?;
    if (productName == null || productName.trim().isEmpty) return null;

    final categoriesTags = product['categories_tags'] as List<dynamic>?;
    final category = _resolveCategory(categoriesTags);
    final imageUrl = product['image_front_small_url'] as String?;
    final code = product['code'] as String? ?? '';

    return BarcodeResult(
      productName: productName.trim(),
      barcode: code,
      category: category,
      imageUrl: imageUrl,
    );
  } catch (_) {
    return null;
  }
}
```

- [ ] **Step 2: Verify the change compiles**

Run: `flutter analyze lib/services/open_food_facts_service.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/open_food_facts_service.dart
git commit -m "feat: add name-based ingredient search via Open Food Facts"
```

---

### Task 3: Use Ingredient Image in Add Flow

**Files:**
- Modify: `lib/screens/add_ingredient_screen.dart`

- [ ] **Step 1: Add state field for resolved image URL**

In `_AddIngredientScreenState`, add a new field:

```dart
String _resolvedImageUrl = '';
```

- [ ] **Step 2: Trigger image lookup when name input loses focus or after autofill**

Add a debounced lookup method. After `_onNameChanged()`, if `_autoFilled` becomes true or name is long enough, fire an async search:

```dart
Future<void> _lookupImage(String name) async {
  if (name.length < 2) return;
  final result = await OpenFoodFactsService.searchByName(name);
  if (result?.imageUrl != null && mounted) {
    setState(() => _resolvedImageUrl = result!.imageUrl!);
  }
}
```

Call `_lookupImage(name)` at the end of `_onNameChanged()` when `defaults != null`:

```dart
void _onNameChanged() {
  final name = _nameController.text.trim();
  final defaults = FoodKnowledge.lookup(name);
  if (defaults != null && !_autoFilled) {
    setState(() {
      _selectedCategory = defaults.category;
      _selectedStorage = defaults.storage;
      _suggestedShelfDays = defaults.shelfLifeDays;
      if (_selectedShelfDays == null && _selectedExpiryDate == null) {
        _applyShelfDays(defaults.shelfLifeDays);
      }
      _autoFilled = true;
    });
    _lookupImage(name);
  } else if (defaults == null) {
    setState(() {
      _autoFilled = false;
      _suggestedShelfDays = null;
    });
  }
}
```

- [ ] **Step 3: Use resolved image URL in barcode scan flow**

In `_scanBarcode()`, after setting the name from the result, also use the image:

```dart
if (result.imageUrl != null) {
  _resolvedImageUrl = result.imageUrl!;
}
```

- [ ] **Step 4: Pass image URL when saving**

In `_save()`, change `imageUrl: ''` to:

```dart
imageUrl: _resolvedImageUrl,
```

- [ ] **Step 5: Reset image URL in `_resetForm()`**

Add to `_resetForm()`:

```dart
_resolvedImageUrl = '';
```

- [ ] **Step 6: Verify the change compiles**

Run: `flutter analyze lib/screens/add_ingredient_screen.dart`
Expected: No errors

- [ ] **Step 7: Commit**

```bash
git add lib/screens/add_ingredient_screen.dart
git commit -m "feat: auto-lookup ingredient image from Open Food Facts on add"
```

---

### Task 4: Add `imageUrl` to Recipe Model

**Files:**
- Modify: `lib/models/recipe.dart`
- Modify: `lib/data/mock_data.dart`

- [ ] **Step 1: Add optional `imageUrl` field to `Recipe`**

```dart
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
  final String? imageUrl;

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
    this.imageUrl,
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
      imageUrl: json['imageUrl'] as String?,
    );
  }
}
```

- [ ] **Step 2: Verify the change compiles**

Run: `flutter analyze lib/models/recipe.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/models/recipe.dart lib/data/mock_data.dart
git commit -m "feat: add optional imageUrl field to Recipe model"
```

---

### Task 5: Create TheMealDB Service

**Files:**
- Create: `lib/services/themealdb_service.dart`

TheMealDB is a free, open API (no key required for test key "1"). It provides recipes with images, ingredients, and instructions.

- [ ] **Step 1: Create the service file**

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';

/// Service for fetching recipes from TheMealDB open API.
class TheMealDbService {
  static const _baseUrl = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 8);

  /// Search recipes by name. Returns up to 10 results.
  static Future<List<Recipe>> searchByName(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/search.php?s=${Uri.encodeComponent(query)}');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null) return [];

      return meals
          .take(10)
          .map((m) => _mealToRecipe(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Search recipes that use a specific ingredient.
  static Future<List<Recipe>> searchByIngredient(String ingredient) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/filter.php?i=${Uri.encodeComponent(ingredient)}',
      );
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null) return [];

      // filter.php returns minimal data; fetch full details for top 5
      final ids = meals
          .take(5)
          .map((m) => (m as Map<String, dynamic>)['idMeal'] as String)
          .toList();

      final recipes = <Recipe>[];
      for (final id in ids) {
        final recipe = await lookupById(id);
        if (recipe != null) recipes.add(recipe);
      }
      return recipes;
    } catch (_) {
      return [];
    }
  }

  /// Lookup a single recipe by TheMealDB ID.
  static Future<Recipe?> lookupById(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/lookup.php?i=$id');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null || meals.isEmpty) return null;

      return _mealToRecipe(meals.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Fetch a random recipe.
  static Future<Recipe?> random() async {
    try {
      final uri = Uri.parse('$_baseUrl/random.php');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final meals = json['meals'] as List<dynamic>?;
      if (meals == null || meals.isEmpty) return null;

      return _mealToRecipe(meals.first as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// Convert TheMealDB meal JSON to our Recipe model.
  static Recipe _mealToRecipe(Map<String, dynamic> meal) {
    final id = meal['idMeal'] as String? ?? '';
    final name = meal['strMeal'] as String? ?? '';
    final category = meal['strCategory'] as String? ?? '';
    final imageUrl = meal['strMealThumb'] as String?;
    final instructions = meal['strInstructions'] as String? ?? '';

    // Extract ingredients (TheMealDB uses strIngredient1..20 + strMeasure1..20)
    final ingredients = <RecipeIngredient>[];
    for (var i = 1; i <= 20; i++) {
      final ing = meal['strIngredient$i'] as String?;
      final measure = meal['strMeasure$i'] as String?;
      if (ing != null && ing.trim().isNotEmpty) {
        ingredients.add(RecipeIngredient(
          name: ing.trim(),
          amount: measure?.trim() ?? '',
        ));
      }
    }

    // Split instructions into steps by newline
    final steps = instructions
        .split(RegExp(r'\r?\n'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    // Extract tags
    final tagsStr = meal['strTags'] as String?;
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    // Estimate difficulty based on ingredient count
    final difficulty = ingredients.length <= 5
        ? 1
        : ingredients.length <= 10
            ? 2
            : 3;

    return Recipe(
      id: 'mealdb_$id',
      name: name,
      category: category,
      difficulty: difficulty,
      cookingMinutes: 30, // TheMealDB doesn't provide cook time; default 30
      description: steps.isNotEmpty ? steps.first : '',
      ingredients: ingredients,
      steps: steps,
      tags: tags,
      imageUrl: imageUrl,
    );
  }
}
```

- [ ] **Step 2: Verify the change compiles**

Run: `flutter analyze lib/services/themealdb_service.dart`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/services/themealdb_service.dart
git commit -m "feat: add TheMealDB service for open recipe API"
```

---

### Task 6: Integrate TheMealDB into Recipe Provider

**Files:**
- Modify: `lib/providers/recipe_provider.dart`

- [ ] **Step 1: Replace static mock recipes with async provider that fetches from TheMealDB**

Replace the entire file content:

```dart
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
```

- [ ] **Step 2: Update dashboard_screen.dart to handle async recipes**

In `lib/screens/dashboard_screen.dart`, change:

```dart
final recommendedRecipes = ref.watch(recommendedRecipesProvider);
```

This line stays the same since `recommendedRecipesProvider` is still a synchronous `Provider`. No change needed here — the async is handled internally by `recommendedRecipesProvider` using `.when()`.

- [ ] **Step 3: Verify the change compiles**

Run: `flutter analyze lib/providers/recipe_provider.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/providers/recipe_provider.dart
git commit -m "feat: integrate TheMealDB API for recipe data with mock fallback"
```

---

### Task 7: Display Recipe Images in UI

**Files:**
- Modify: `lib/screens/recipe_detail_screen.dart`
- Modify: `lib/widgets/recipe_card.dart`

- [ ] **Step 1: Update `recipe_detail_screen.dart` to show image when available**

Replace the `FlexibleSpaceBar` background section (around line 30-35):

```dart
flexibleSpace: FlexibleSpaceBar(
  background: recipe.imageUrl != null
      ? Image.network(
          recipe.imageUrl!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            color: AppColors.surfaceContainerLow,
            child: const Icon(Icons.restaurant, size: 64),
          ),
        )
      : Container(
          color: AppColors.surfaceContainerLow,
          child: const Icon(Icons.restaurant, size: 64),
        ),
),
```

- [ ] **Step 2: Update `recipe_card.dart` to show thumbnail when available**

Replace the thumbnail section (around line 32-48):

```dart
// Thumbnail
ClipRRect(
  borderRadius: const BorderRadius.only(
    topLeft: Radius.circular(16),
    bottomLeft: Radius.circular(16),
  ),
  child: recipe.imageUrl != null
      ? Image.network(
          recipe.imageUrl!,
          width: 96,
          height: 96,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            width: 96,
            height: 96,
            color: AppColors.surfaceContainerLow,
            child: const Icon(Icons.restaurant, color: AppColors.outline),
          ),
        )
      : Container(
          width: 96,
          height: 96,
          color: AppColors.surfaceContainerLow,
          child: const Icon(Icons.restaurant, color: AppColors.outline),
        ),
),
```

- [ ] **Step 3: Verify the changes compile**

Run: `flutter analyze lib/screens/recipe_detail_screen.dart lib/widgets/recipe_card.dart`
Expected: No errors

- [ ] **Step 4: Commit**

```bash
git add lib/screens/recipe_detail_screen.dart lib/widgets/recipe_card.dart
git commit -m "feat: display recipe images from API in detail screen and cards"
```

---

### Task 8: Full Integration Verify

- [ ] **Step 1: Run full analysis**

Run: `flutter analyze`
Expected: No errors (warnings about unused parameters in batch_entry_screen.dart are acceptable)

- [ ] **Step 2: Build check**

Run: `flutter build apk --debug 2>&1 | tail -5`
Expected: BUILD SUCCESSFUL

- [ ] **Step 3: Final commit if any loose fixes were needed**

```bash
git add -A
git status
# Only commit if there are changes
git commit -m "fix: resolve any remaining compile issues from API integration"
```
