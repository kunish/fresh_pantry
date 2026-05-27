import '../models/storage_area.dart';
import 'food_categories.dart';

class FoodDefaults {
  final String category;
  final IconType storage;
  final int shelfLifeDays;

  const FoodDefaults(this.category, this.storage, this.shelfLifeDays);
}

/// Maps food name keywords to smart defaults for category, storage, and shelf life.
class FoodKnowledge {
  static const _entries = <String, FoodDefaults>{
    // ── 乳品蛋类 → 冰箱 ──
    '牛奶': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 7),
    '酸奶': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 14),
    '奶酪': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 30),
    '芝士': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 30),
    '黄油': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 60),
    '奶油': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 14),
    '鸡蛋': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 30),
    '鸭蛋': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 30),
    '蛋': FoodDefaults(FoodCategories.dairyAndEggs, IconType.fridge, 30),

    // ── 果蔬生鲜 → 冰箱 ──
    '番茄': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '西红柿': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '菠菜': FoodDefaults('果蔬生鲜', IconType.fridge, 3),
    '生菜': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '白菜': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '青菜': FoodDefaults('果蔬生鲜', IconType.fridge, 3),
    '胡萝卜': FoodDefaults('果蔬生鲜', IconType.fridge, 14),
    '萝卜': FoodDefaults('果蔬生鲜', IconType.fridge, 14),
    '土豆': FoodDefaults('果蔬生鲜', IconType.pantry, 21),
    '洋葱': FoodDefaults('果蔬生鲜', IconType.pantry, 30),
    '大蒜': FoodDefaults('果蔬生鲜', IconType.pantry, 30),
    '姜': FoodDefaults('果蔬生鲜', IconType.pantry, 21),
    '黄瓜': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '茄子': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '辣椒': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '青椒': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '西兰花': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '花菜': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '芹菜': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '蘑菇': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '豆腐': FoodDefaults('果蔬生鲜', IconType.fridge, 3),
    '苹果': FoodDefaults('果蔬生鲜', IconType.fridge, 14),
    '香蕉': FoodDefaults('果蔬生鲜', IconType.pantry, 5),
    '橙子': FoodDefaults('果蔬生鲜', IconType.fridge, 14),
    '柠檬': FoodDefaults('果蔬生鲜', IconType.fridge, 21),
    '葡萄': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '草莓': FoodDefaults('果蔬生鲜', IconType.fridge, 3),
    '蓝莓': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '西瓜': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '牛油果': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '芒果': FoodDefaults('果蔬生鲜', IconType.fridge, 5),
    '豆芽': FoodDefaults('果蔬生鲜', IconType.fridge, 2),
    '韭菜': FoodDefaults('果蔬生鲜', IconType.fridge, 3),
    '葱': FoodDefaults('果蔬生鲜', IconType.fridge, 7),
    '香菜': FoodDefaults('果蔬生鲜', IconType.fridge, 5),

    // ── 肉类海鲜 → 冰箱 ──
    '鸡肉': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '鸡胸': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '鸡腿': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '鸡翅': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '猪肉': FoodDefaults('肉类海鲜', IconType.fridge, 3),
    '排骨': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '五花肉': FoodDefaults('肉类海鲜', IconType.fridge, 3),
    '牛肉': FoodDefaults('肉类海鲜', IconType.fridge, 3),
    '牛排': FoodDefaults('肉类海鲜', IconType.fridge, 90),
    '羊肉': FoodDefaults('肉类海鲜', IconType.fridge, 3),
    '培根': FoodDefaults('肉类海鲜', IconType.fridge, 7),
    '香肠': FoodDefaults('肉类海鲜', IconType.fridge, 7),
    '火腿': FoodDefaults('肉类海鲜', IconType.fridge, 7),
    '鱼': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '三文鱼': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '虾': FoodDefaults('肉类海鲜', IconType.fridge, 90),
    '虾仁': FoodDefaults('肉类海鲜', IconType.fridge, 90),
    '蟹': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '贝': FoodDefaults('肉类海鲜', IconType.fridge, 2),
    '肉丸': FoodDefaults('肉类海鲜', IconType.fridge, 60),
    '饺子': FoodDefaults('肉类海鲜', IconType.fridge, 90),
    '馄饨': FoodDefaults('肉类海鲜', IconType.fridge, 90),

    // ── 其他 → 食品柜 ──
    '米': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '大米': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '面条': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '挂面': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '意面': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '意大利面': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '面粉': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '面包': FoodDefaults(FoodCategories.other, IconType.pantry, 3),
    '法棍': FoodDefaults(FoodCategories.other, IconType.pantry, 2),
    '吐司': FoodDefaults(FoodCategories.other, IconType.pantry, 5),
    '饼干': FoodDefaults(FoodCategories.other, IconType.pantry, 90),
    '麦片': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '燕麦': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '糖': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '白糖': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '红糖': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '蜂蜜': FoodDefaults(FoodCategories.other, IconType.pantry, 730),
    '食用油': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '橄榄油': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '花生油': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '菜籽油': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '醋': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '酱油': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '料酒': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '罐头': FoodDefaults(FoodCategories.other, IconType.pantry, 730),
    '咖啡': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '茶': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '茶叶': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '巧克力': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '坚果': FoodDefaults(FoodCategories.other, IconType.pantry, 90),
    '花生': FoodDefaults(FoodCategories.other, IconType.pantry, 90),
    '核桃': FoodDefaults(FoodCategories.other, IconType.pantry, 90),
    '芝麻': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '淀粉': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '番茄酱': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '豆瓣酱': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '老干妈': FoodDefaults(FoodCategories.other, IconType.pantry, 365),
    '方便面': FoodDefaults(FoodCategories.other, IconType.pantry, 180),
    '速冻': FoodDefaults(FoodCategories.other, IconType.fridge, 180),
    '冰淇淋': FoodDefaults(FoodCategories.other, IconType.fridge, 180),

    // ── 香料草本 → 食品柜 ──
    '盐': FoodDefaults('香料草本', IconType.pantry, 1825),
    '海盐': FoodDefaults('香料草本', IconType.pantry, 1825),
    '胡椒': FoodDefaults('香料草本', IconType.pantry, 730),
    '黑胡椒': FoodDefaults('香料草本', IconType.pantry, 730),
    '白胡椒': FoodDefaults('香料草本', IconType.pantry, 730),
    '花椒': FoodDefaults('香料草本', IconType.pantry, 365),
    '八角': FoodDefaults('香料草本', IconType.pantry, 365),
    '桂皮': FoodDefaults('香料草本', IconType.pantry, 365),
    '香叶': FoodDefaults('香料草本', IconType.pantry, 365),
    '孜然': FoodDefaults('香料草本', IconType.pantry, 365),
    '辣椒粉': FoodDefaults('香料草本', IconType.pantry, 365),
    '咖喱': FoodDefaults('香料草本', IconType.pantry, 365),
    '五香粉': FoodDefaults('香料草本', IconType.pantry, 365),
    '香草': FoodDefaults('香料草本', IconType.fridge, 7),
    '薄荷': FoodDefaults('香料草本', IconType.fridge, 5),
    '迷迭香': FoodDefaults('香料草本', IconType.fridge, 7),
    '罗勒': FoodDefaults('香料草本', IconType.fridge, 5),
    '香草精': FoodDefaults('香料草本', IconType.pantry, 365),
  };

  // ── Chinese → English food name mapping for API search ──
  static const _englishNames = <String, String>{
    '牛奶': 'milk',
    '酸奶': 'yogurt',
    '奶酪': 'cheese',
    '芝士': 'cheese',
    '黄油': 'butter',
    '奶油': 'cream',
    '鸡蛋': 'egg',
    '鸭蛋': 'egg',
    '蛋': 'egg',
    '番茄': 'tomato',
    '西红柿': 'tomato',
    '菠菜': 'spinach',
    '生菜': 'lettuce',
    '白菜': 'cabbage',
    '青菜': 'greens',
    '胡萝卜': 'carrot',
    '萝卜': 'radish',
    '土豆': 'potato',
    '洋葱': 'onion',
    '大蒜': 'garlic',
    '姜': 'ginger',
    '黄瓜': 'cucumber',
    '茄子': 'eggplant',
    '辣椒': 'chili',
    '青椒': 'pepper',
    '西兰花': 'broccoli',
    '花菜': 'cauliflower',
    '芹菜': 'celery',
    '蘑菇': 'mushroom',
    '豆腐': 'tofu',
    '苹果': 'apple',
    '香蕉': 'banana',
    '橙子': 'orange',
    '柠檬': 'lemon',
    '葡萄': 'grape',
    '草莓': 'strawberry',
    '蓝莓': 'blueberry',
    '西瓜': 'watermelon',
    '牛油果': 'avocado',
    '芒果': 'mango',
    '鸡肉': 'chicken',
    '鸡胸': 'chicken breast',
    '鸡腿': 'chicken leg',
    '鸡翅': 'chicken wing',
    '猪肉': 'pork',
    '排骨': 'ribs',
    '五花肉': 'pork belly',
    '牛肉': 'beef',
    '牛排': 'steak',
    '羊肉': 'lamb',
    '培根': 'bacon',
    '香肠': 'sausage',
    '火腿': 'ham',
    '鱼': 'fish',
    '三文鱼': 'salmon',
    '虾': 'shrimp',
    '蟹': 'crab',
    '米': 'rice',
    '大米': 'rice',
    '面条': 'noodle',
    '意面': 'pasta',
    '意大利面': 'pasta',
    '面粉': 'flour',
    '面包': 'bread',
    '法棍': 'baguette',
    '糖': 'sugar',
    '蜂蜜': 'honey',
    '橄榄油': 'olive oil',
    '巧克力': 'chocolate',
    '咖啡': 'coffee',
    '茶': 'tea',
  };

  /// Look up the English name for a Chinese food name.
  /// Matches the longest keyword found in the name.
  static String? englishName(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;

    String? best;
    int bestLen = 0;

    for (final entry in _englishNames.entries) {
      if (lower.contains(entry.key) && entry.key.length > bestLen) {
        best = entry.value;
        bestLen = entry.key.length;
      }
    }
    return best;
  }

  /// Look up smart defaults for an ingredient name.
  /// Matches against keywords in the name (longest match wins).
  static FoodDefaults? lookup(String name) {
    final lower = name.trim().toLowerCase();
    if (lower.isEmpty) return null;

    FoodDefaults? best;
    int bestLen = 0;

    for (final entry in _entries.entries) {
      if (lower.contains(entry.key) && entry.key.length > bestLen) {
        best = entry.value;
        bestLen = entry.key.length;
      }
    }
    return best;
  }

  /// Resolve the stable app category for a food name.
  static String categoryFor(
    String name, {
    String fallback = FoodCategories.other,
  }) {
    final normalized = FoodCategories.normalize(lookup(name)?.category);
    return normalized ?? FoodCategories.dropdownValue(fallback);
  }

  /// Common shelf life presets for quick-select UI.
  static const shelfLifePresets = [3, 7, 14, 30];

  /// Common units.
  static const units = ['个', '瓶', '袋', '盒', '包', 'g', 'kg', 'ml', 'L'];
}
