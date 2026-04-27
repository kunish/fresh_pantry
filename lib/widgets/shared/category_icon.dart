import 'package:flutter/material.dart';

import '../../data/food_categories.dart';
import '../../theme/app_theme.dart';

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
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: muted ? AppColors.surfaceContainerHigh : AppColors.primaryFixed,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Icon(
        categoryIconFor(category),
        color: muted ? AppColors.outline : AppColors.primary,
        size: iconSize,
      ),
    );
  }
}
