import 'dart:convert';
import 'package:http/http.dart' as http;

/// Result returned from barcode lookup.
class BarcodeResult {
  final String productName;
  final String? category;
  final String barcode;

  const BarcodeResult({
    required this.productName,
    required this.barcode,
    this.category,
  });
}

/// Service for querying product info from Open Food Facts API.
class OpenFoodFactsService {
  static const _baseUrl = 'https://world.openfoodfacts.org/api/v2/product';
  static const _timeout = Duration(seconds: 8);

  /// Category keyword mapping: OFF categories_tags substring → app category.
  static const _categoryMapping = <String, String>{
    // 乳制品与蛋类
    'dairy': '乳制品与蛋类',
    'milk': '乳制品与蛋类',
    'cheese': '乳制品与蛋类',
    'yogurt': '乳制品与蛋类',
    'butter': '乳制品与蛋类',
    'cream': '乳制品与蛋类',
    'egg': '乳制品与蛋类',
    'lait': '乳制品与蛋类',
    'fromage': '乳制品与蛋类',
    // 新鲜蔬果
    'fruit': '新鲜蔬果',
    'vegetable': '新鲜蔬果',
    'legume': '新鲜蔬果',
    'salad': '新鲜蔬果',
    'produce': '新鲜蔬果',
    // 肉类与海鲜
    'meat': '肉类与海鲜',
    'beef': '肉类与海鲜',
    'pork': '肉类与海鲜',
    'chicken': '肉类与海鲜',
    'poultry': '肉类与海鲜',
    'fish': '肉类与海鲜',
    'seafood': '肉类与海鲜',
    'shrimp': '肉类与海鲜',
    'viande': '肉类与海鲜',
    'poisson': '肉类与海鲜',
    // 香料与草本
    'spice': '香料与草本',
    'herb': '香料与草本',
    'seasoning': '香料与草本',
    'condiment': '香料与草本',
    'sauce': '香料与草本',
    'épice': '香料与草本',
    // 食品柜常备 (pantry staples — broad catch)
    'cereal': '食品柜常备',
    'pasta': '食品柜常备',
    'rice': '食品柜常备',
    'bread': '食品柜常备',
    'flour': '食品柜常备',
    'oil': '食品柜常备',
    'sugar': '食品柜常备',
    'snack': '食品柜常备',
    'beverage': '食品柜常备',
    'drink': '食品柜常备',
    'canned': '食品柜常备',
    'conserve': '食品柜常备',
    'biscuit': '食品柜常备',
    'chocolate': '食品柜常备',
    'coffee': '食品柜常备',
    'tea': '食品柜常备',
    'juice': '食品柜常备',
    'water': '食品柜常备',
    'noodle': '食品柜常备',
    'grain': '食品柜常备',
  };

  /// Look up a barcode. Returns a [BarcodeResult] on success, `null` if not
  /// found or on network / parse error.
  static Future<BarcodeResult?> lookup(String barcode) async {
    try {
      final uri = Uri.parse('$_baseUrl/$barcode.json');
      final response = await http.get(uri).timeout(_timeout);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['status'] != 1) return null;

      final product = json['product'] as Map<String, dynamic>?;
      if (product == null) return null;

      // Try product_name first, then product_name_en, then generic_name.
      final name = _firstNonEmpty([
        product['product_name'] as String?,
        product['product_name_en'] as String?,
        product['generic_name'] as String?,
      ]);

      if (name == null) return null;

      // Resolve category from categories_tags list.
      final categoriesTags = product['categories_tags'] as List<dynamic>?;
      final category = _resolveCategory(categoriesTags);

      return BarcodeResult(
        productName: name,
        barcode: barcode,
        category: category,
      );
    } catch (_) {
      return null;
    }
  }

  /// Return the first non-null, non-empty string from [candidates].
  static String? _firstNonEmpty(List<String?> candidates) {
    for (final s in candidates) {
      if (s != null && s.trim().isNotEmpty) return s.trim();
    }
    return null;
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
}
