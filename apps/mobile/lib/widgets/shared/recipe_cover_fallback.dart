import 'package:flutter/material.dart';

import '../../theme/fk_category_palette.dart';

/// 菜谱封面无图时的占位 —— 按菜式分类(荤菜/素菜/主食/水产…)选语义色调 + 对应图标,
/// 配一道柔和斜向渐变,让「没有成品图」看起来是设计内的状态而非加载失败。
///
/// 注意:这里的分类是**菜式**分类(`Recipe.category`),与食材分类不同,故不复用
/// `CategoryIconAvatar`(后者走食材分类映射,菜式分类喂进去会全部落到默认色)。
class RecipeCoverFallback extends StatelessWidget {
  final String? category;
  final double iconSize;

  const RecipeCoverFallback({
    super.key,
    required this.category,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    final visual = _visualFor(category);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            visual.colors.tint,
            Color.lerp(visual.colors.tint, Colors.white, 0.45)!,
          ],
        ),
      ),
      child: Center(
        child: Icon(visual.icon, size: iconSize, color: visual.colors.ink),
      ),
    );
  }
}

typedef _RecipeVisual = ({FkCatColors colors, IconData icon});

_RecipeVisual _visualFor(String? category) {
  return switch (category) {
    '荤菜' => (colors: FkCategoryPalette.meat, icon: Icons.kebab_dining_rounded),
    '素菜' => (colors: FkCategoryPalette.veg, icon: Icons.eco_rounded),
    '主食' => (colors: FkCategoryPalette.grain, icon: Icons.rice_bowl_rounded),
    '水产' => (colors: FkCategoryPalette.sea, icon: Icons.set_meal_rounded),
    '早餐' => (
      colors: FkCategoryPalette.snack,
      icon: Icons.bakery_dining_rounded,
    ),
    '饮品' => (colors: FkCategoryPalette.drink, icon: Icons.local_cafe_rounded),
    '汤羹' => (colors: FkCategoryPalette.sea, icon: Icons.ramen_dining_rounded),
    '甜品' => (colors: FkCategoryPalette.fruit, icon: Icons.cake_rounded),
    '半成品' => (colors: FkCategoryPalette.sauce, icon: Icons.blender_rounded),
    '酱料' => (colors: FkCategoryPalette.sauce, icon: Icons.water_drop_rounded),
    _ => (colors: FkCategoryPalette.grain, icon: Icons.restaurant_rounded),
  };
}
