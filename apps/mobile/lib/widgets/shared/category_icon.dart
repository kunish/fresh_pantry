import 'package:flutter/material.dart';

import '../../data/food_categories.dart';
import '../../theme/app_theme.dart';
import '../../theme/fk_category_palette.dart';
import 'cat_icon.dart';

/// 把项目内 5 大类(`FoodCategories`)映射到 FK 设计稿的 9 个细分类 id。
/// 粗到细是 lossy 的:`果蔬生鲜` 统一走 `veg`、`肉类海鲜` 统一走 `meat`,
/// 调用方若知道更具体的语义可绕过本函数直接传 `'fruit'` / `'sea'` 等。
String fkCategoryIdFor(String? category) {
  return switch (FoodCategories.dropdownValue(category)) {
    FoodCategories.dairyAndEggs => 'dairy',
    FoodCategories.freshProduce => 'veg',
    FoodCategories.meatAndSeafood => 'meat',
    FoodCategories.herbsAndSpices => 'sauce',
    _ => 'grain',
  };
}

/// `fkCategoryIdFor` 的反向(粗化):把 FK 细分类 id 映回项目内 5 大类
/// (`FoodCategories`)的规范名。供首页/库存页展示分类标签时使用,确保与
/// 「我的食材」筛选用的同一套分类名一致(单一数据源)。
String foodCategoryForFkId(String catId) {
  return switch (catId) {
    'dairy' => FoodCategories.dairyAndEggs,
    'veg' || 'fruit' => FoodCategories.freshProduce,
    'meat' || 'sea' => FoodCategories.meatAndSeafood,
    'sauce' => FoodCategories.herbsAndSpices,
    _ => FoodCategories.other,
  };
}

/// 旧 API,保留以兼容暂未迁移的 caller。新代码请用 `CatIcon`。
IconData categoryIconFor(String? category) {
  return switch (FoodCategories.dropdownValue(category)) {
    FoodCategories.dairyAndEggs => Icons.egg_outlined,
    FoodCategories.freshProduce => Icons.eco_outlined,
    FoodCategories.meatAndSeafood => Icons.set_meal_outlined,
    FoodCategories.herbsAndSpices => Icons.spa_outlined,
    _ => Icons.restaurant_outlined,
  };
}

class CategoryIconAvatar extends StatelessWidget {
  final String? category;
  final double size;
  final double iconSize;
  final bool muted;
  final double borderRadius;

  /// 当 `category` 是 FK 细分类 id (veg/fruit/meat/sea/dairy/drink/sauce/
  /// grain/snack) 时直接用,否则走 `FoodCategories` 粗类映射。
  const CategoryIconAvatar({
    super.key,
    required this.category,
    required this.size,
    required this.iconSize,
    this.muted = false,
    this.borderRadius = 12,
  });

  @override
  Widget build(BuildContext context) {
    final catId = FkCategoryPalette.all.containsKey(category)
        ? category!
        : fkCategoryIdFor(category);
    final palette = FkCategoryPalette.of(catId);
    final tint = muted ? AppColors.surfaceContainerHigh : palette.tint;
    final ink = muted ? AppColors.outline : palette.ink;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      alignment: Alignment.center,
      child: CatIcon(category: catId, size: iconSize, color: ink),
    );
  }
}
