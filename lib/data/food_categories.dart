class FoodCategories {
  static const dairyAndEggs = '乳品蛋类';
  static const freshProduce = '果蔬生鲜';
  static const meatAndSeafood = '肉类海鲜';
  static const herbsAndSpices = '香料草本';
  static const other = '其他';

  static const removedPantryStaples = '食品柜常备';

  static const _aliases = {
    dairyAndEggs: dairyAndEggs,
    '乳制品与蛋类': dairyAndEggs,
    '乳制品与干货': dairyAndEggs,
    '乳制品': dairyAndEggs,
    '乳品': dairyAndEggs,
    '蛋类': dairyAndEggs,
    '蛋': dairyAndEggs,
    freshProduce: freshProduce,
    '新鲜蔬果': freshProduce,
    '蔬菜': freshProduce,
    '水果': freshProduce,
    '果蔬': freshProduce,
    '生鲜': freshProduce,
    meatAndSeafood: meatAndSeafood,
    '肉类与海鲜': meatAndSeafood,
    '肉类': meatAndSeafood,
    '海鲜': meatAndSeafood,
    '蛋白质': meatAndSeafood,
    herbsAndSpices: herbsAndSpices,
    '香料与草本': herbsAndSpices,
    '香料': herbsAndSpices,
    '草本': herbsAndSpices,
    '调味品': herbsAndSpices,
    '调味料': herbsAndSpices,
    other: other,
    removedPantryStaples: other,
    '谷物': other,
    '主食': other,
    '干货': other,
  };

  static const values = [
    dairyAndEggs,
    freshProduce,
    meatAndSeafood,
    herbsAndSpices,
    other,
  ];

  static String? normalize(String? category) {
    final trimmed = category?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return _aliases[trimmed] ?? other;
  }

  static String dropdownValue(String? category) {
    return normalize(category) ?? other;
  }
}
