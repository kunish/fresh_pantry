import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/recipe.dart';

/// Service for fetching recipes from TheMealDB open API.
class TheMealDbService {
  static const _baseUrl = 'https://www.themealdb.com/api/json/v1/1';
  static const _timeout = Duration(seconds: 8);
  static const _retryCount = 1;
  static const _retryDelay = Duration(milliseconds: 500);
  static const _maxSearchResults = 10;
  static const _maxIngredientResults = 5;
  static const _maxIngredients = 20;
  static const _easyIngredientThreshold = 5;
  static const _mediumIngredientThreshold = 10;
  static const _defaultCookingMinutes = 30;
  static const _headers = <String, String>{
    'User-Agent': 'FreshPantry/1.0 (Flutter)',
  };

  /// Search recipes by name. Returns up to [_maxSearchResults] results.
  static Future<List<Recipe>> searchByName(String query) async {
    try {
      final uri = Uri.parse('$_baseUrl/search.php?s=${Uri.encodeComponent(query)}');
      final response = await _fetch(uri);

      if (response.statusCode != 200) return [];

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return [];

      final meals = _asList(json['meals']);
      if (meals == null) return [];

      return meals
          .take(_maxSearchResults)
          .whereType<Map<String, dynamic>>()
          .map(_mealToRecipe)
          .toList();
    } on TimeoutException catch (e, stack) {
      debugPrint('TheMealDB searchByName timeout: $e\n$stack');
      return [];
    } on http.ClientException catch (e, stack) {
      debugPrint('TheMealDB searchByName HTTP error: $e\n$stack');
      return [];
    } on FormatException catch (e, stack) {
      debugPrint('TheMealDB searchByName format error: $e\n$stack');
      return [];
    } catch (e, stack) {
      debugPrint('TheMealDB searchByName unexpected error: $e\n$stack');
      return [];
    }
  }

  /// Search recipes that use a specific ingredient.
  static Future<List<Recipe>> searchByIngredient(String ingredient) async {
    try {
      final uri = Uri.parse(
        '$_baseUrl/filter.php?i=${Uri.encodeComponent(ingredient)}',
      );
      final response = await _fetch(uri);

      if (response.statusCode != 200) return [];

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return [];

      final meals = _asList(json['meals']);
      if (meals == null) return [];

      // filter.php returns minimal data; fetch full details for top [_maxIngredientResults]
      final ids = meals
          .take(_maxIngredientResults)
          .whereType<Map<String, dynamic>>()
          .map((m) => m['idMeal']?.toString())
          .whereType<String>()
          .toList();

      final recipes = <Recipe>[];
      for (final id in ids) {
        final recipe = await lookupById(id);
        if (recipe != null) recipes.add(recipe);
      }
      return recipes;
    } on TimeoutException catch (e, stack) {
      debugPrint('TheMealDB searchByIngredient timeout: $e\n$stack');
      return [];
    } on http.ClientException catch (e, stack) {
      debugPrint('TheMealDB searchByIngredient HTTP error: $e\n$stack');
      return [];
    } on FormatException catch (e, stack) {
      debugPrint('TheMealDB searchByIngredient format error: $e\n$stack');
      return [];
    } catch (e, stack) {
      debugPrint('TheMealDB searchByIngredient unexpected error: $e\n$stack');
      return [];
    }
  }

  /// Lookup a single recipe by TheMealDB ID.
  static Future<Recipe?> lookupById(String id) async {
    try {
      final uri = Uri.parse('$_baseUrl/lookup.php?i=$id');
      final response = await _fetch(uri);

      if (response.statusCode != 200) return null;

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return null;

      final meals = _asList(json['meals']);
      if (meals == null || meals.isEmpty) return null;

      final first = meals.first;
      if (first is! Map<String, dynamic>) return null;
      return _mealToRecipe(first);
    } on TimeoutException catch (e, stack) {
      debugPrint('TheMealDB lookupById timeout: $e\n$stack');
      return null;
    } on http.ClientException catch (e, stack) {
      debugPrint('TheMealDB lookupById HTTP error: $e\n$stack');
      return null;
    } on FormatException catch (e, stack) {
      debugPrint('TheMealDB lookupById format error: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('TheMealDB lookupById unexpected error: $e\n$stack');
      return null;
    }
  }

  /// Fetch a random recipe.
  static Future<Recipe?> random() async {
    try {
      final uri = Uri.parse('$_baseUrl/random.php');
      final response = await _fetch(uri);

      if (response.statusCode != 200) return null;

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return null;

      final meals = _asList(json['meals']);
      if (meals == null || meals.isEmpty) return null;

      final first = meals.first;
      if (first is! Map<String, dynamic>) return null;
      return _mealToRecipe(first);
    } on TimeoutException catch (e, stack) {
      debugPrint('TheMealDB random timeout: $e\n$stack');
      return null;
    } on http.ClientException catch (e, stack) {
      debugPrint('TheMealDB random HTTP error: $e\n$stack');
      return null;
    } on FormatException catch (e, stack) {
      debugPrint('TheMealDB random format error: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('TheMealDB random unexpected error: $e\n$stack');
      return null;
    }
  }

  /// Convert TheMealDB meal JSON to our Recipe model.
  static Recipe _mealToRecipe(Map<String, dynamic> meal) {
    final id = meal['idMeal']?.toString() ?? '';
    final name = _asString(meal['strMeal']) ?? '';
    final category = _asString(meal['strCategory']) ?? '';
    final imageUrl = _asString(meal['strMealThumb']);
    final instructions = _asString(meal['strInstructions']) ?? '';

    // Extract ingredients (TheMealDB uses strIngredient1..20 + strMeasure1..20)
    final ingredients = <RecipeIngredient>[];
    for (var i = 1; i <= _maxIngredients; i++) {
      final ing = _asString(meal['strIngredient$i']);
      final measure = _asString(meal['strMeasure$i']);
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
    final tagsStr = _asString(meal['strTags']);
    final tags = tagsStr != null
        ? tagsStr.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList()
        : <String>[];

    // Estimate difficulty based on ingredient count
    final difficulty = ingredients.length <= _easyIngredientThreshold
        ? 1
        : ingredients.length <= _mediumIngredientThreshold
            ? 2
            : 3;

    return Recipe(
      id: 'mealdb_$id',
      name: name,
      category: category,
      difficulty: difficulty,
      cookingMinutes: _defaultCookingMinutes,
      description: steps.isNotEmpty ? steps.first : '',
      ingredients: ingredients,
      steps: steps,
      tags: tags,
      imageUrl: imageUrl,
    );
  }

  /// Perform an HTTP GET with retry logic.
  static Future<http.Response> _fetch(Uri uri) async {
    final client = http.Client();
    try {
      for (var attempt = 0; attempt <= _retryCount; attempt++) {
        try {
          final response =
              await client.get(uri, headers: _headers).timeout(_timeout);
          return response;
        } on TimeoutException {
          if (attempt == _retryCount) rethrow;
        } on http.ClientException {
          if (attempt == _retryCount) rethrow;
        }
        await Future<void>.delayed(_retryDelay);
      }
      throw StateError('Unreachable');
    } finally {
      client.close();
    }
  }

  /// Safely cast [value] to [Map<String, dynamic>].
  static Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  /// Safely cast [value] to [List<dynamic>].
  static List<dynamic>? _asList(dynamic value) {
    if (value is List<dynamic>) return value;
    return null;
  }

  /// Safely cast [value] to [String].
  static String? _asString(dynamic value) {
    if (value is String) return value;
    return null;
  }
}
