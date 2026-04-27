import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../data/food_categories.dart';

/// Result returned from Open Food Facts name search.
class FoodSearchResult {
  final String productName;
  final String? category;
  final String? imageUrl;

  const FoodSearchResult({
    required this.productName,
    this.category,
    this.imageUrl,
  });
}

/// Service for querying product info from Open Food Facts API.
class OpenFoodFactsService {
  static const _searchUrl = 'https://world.openfoodfacts.org/cgi/search.pl';
  static const _timeout = Duration(seconds: 8);
  static const _retryCount = 1;
  static const _retryDelay = Duration(milliseconds: 500);
  static const _maxSearchResults = 1;
  static const _headers = <String, String>{
    'User-Agent': 'FreshPantry/1.0 (Flutter)',
  };

  /// Category keyword mapping: OFF categories_tags substring → app category.
  static const _categoryMapping = <String, String>{
    // 乳品蛋类
    'dairy': '乳品蛋类',
    'milk': '乳品蛋类',
    'cheese': '乳品蛋类',
    'yogurt': '乳品蛋类',
    'butter': '乳品蛋类',
    'cream': '乳品蛋类',
    'egg': '乳品蛋类',
    'lait': '乳品蛋类',
    'fromage': '乳品蛋类',
    // 果蔬生鲜
    'fruit': '果蔬生鲜',
    'vegetable': '果蔬生鲜',
    'legume': '果蔬生鲜',
    'salad': '果蔬生鲜',
    'produce': '果蔬生鲜',
    'fresh': '果蔬生鲜',
    // 肉类海鲜
    'meat': '肉类海鲜',
    'beef': '肉类海鲜',
    'pork': '肉类海鲜',
    'chicken': '肉类海鲜',
    'poultry': '肉类海鲜',
    'fish': '肉类海鲜',
    'seafood': '肉类海鲜',
    'shrimp': '肉类海鲜',
    'viande': '肉类海鲜',
    'poisson': '肉类海鲜',
    // 香料草本
    'spice': '香料草本',
    'herb': '香料草本',
    'seasoning': '香料草本',
    'pepper': '香料草本',
    'salt': '香料草本',
    'condiment': FoodCategories.herbsAndSpices,
    'sauce': FoodCategories.herbsAndSpices,
    'épice': '香料草本',
    // Broad shelf-stable catchall.
    'cereal': FoodCategories.other,
    'pasta': FoodCategories.other,
    'rice': FoodCategories.other,
    'bread': FoodCategories.other,
    'flour': FoodCategories.other,
    'oil': FoodCategories.other,
    'sugar': FoodCategories.other,
    'snack': FoodCategories.other,
    'beverage': FoodCategories.other,
    'drink': FoodCategories.other,
    'canned': FoodCategories.other,
    'conserve': FoodCategories.other,
    'biscuit': FoodCategories.other,
    'chocolate': FoodCategories.other,
    'coffee': FoodCategories.other,
    'tea': FoodCategories.other,
    'juice': FoodCategories.other,
    'water': FoodCategories.other,
    'noodle': FoodCategories.other,
    'grain': FoodCategories.other,
  };

  /// Search for a product by name. Returns the best match as a [FoodSearchResult]
  /// or `null` if nothing relevant is found.
  static Future<FoodSearchResult?> searchByName(String name) async {
    try {
      final uri = Uri.parse(
        '$_searchUrl'
        '?search_terms=${Uri.encodeComponent(name)}'
        '&search_simple=1&action=process&json=1&page_size=$_maxSearchResults'
        '&fields=product_name,categories_tags,image_front_small_url',
      );
      final response = await _fetch(uri);

      if (response.statusCode != 200) return null;

      final json = _asMap(jsonDecode(response.body));
      if (json == null) return null;

      final products = _asList(json['products']);
      if (products == null || products.isEmpty) return null;

      final first = products.first;
      final product = _asMap(first);
      if (product == null) return null;

      final productName = _asString(product['product_name']);
      if (productName == null || productName.trim().isEmpty) return null;

      final categoriesTags = _asList(product['categories_tags']);
      final category = _resolveCategory(categoriesTags);
      final imageUrl = _asString(product['image_front_small_url']);

      return FoodSearchResult(
        productName: productName.trim(),
        category: category,
        imageUrl: imageUrl,
      );
    } on TimeoutException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName timeout: $e\n$stack');
      return null;
    } on http.ClientException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName HTTP error: $e\n$stack');
      return null;
    } on FormatException catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName format error: $e\n$stack');
      return null;
    } catch (e, stack) {
      debugPrint('OpenFoodFacts searchByName unexpected error: $e\n$stack');
      return null;
    }
  }

  /// Match OFF categories_tags against keyword map. Returns the first matched
  /// app category or `null`.
  static String? _resolveCategory(List<dynamic>? tags) {
    if (tags == null || tags.isEmpty) return null;

    for (final tag in tags) {
      final lower = tag.toString().toLowerCase();
      for (final entry in _categoryMapping.entries) {
        if (lower.contains(entry.key)) {
          return entry.value;
        }
      }
    }
    return null;
  }

  /// Perform an HTTP GET with retry logic.
  static Future<http.Response> _fetch(Uri uri) async {
    final client = http.Client();
    try {
      for (var attempt = 0; attempt <= _retryCount; attempt++) {
        try {
          final response = await client
              .get(uri, headers: _headers)
              .timeout(_timeout);
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
