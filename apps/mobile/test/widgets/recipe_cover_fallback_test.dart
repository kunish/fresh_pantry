import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/fk_category_palette.dart';
import 'package:fresh_pantry/widgets/shared/recipe_cover_fallback.dart';

Future<void> _pump(WidgetTester tester, String? category) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: RecipeCoverFallback(category: category),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('每个菜式分类映射到各自的图标', (tester) async {
    const expected = {
      '荤菜': Icons.kebab_dining_rounded,
      '素菜': Icons.eco_rounded,
      '主食': Icons.rice_bowl_rounded,
      '水产': Icons.set_meal_rounded,
      '早餐': Icons.bakery_dining_rounded,
      '饮品': Icons.local_cafe_rounded,
      '汤羹': Icons.ramen_dining_rounded,
      '甜品': Icons.cake_rounded,
      '半成品': Icons.blender_rounded,
      '酱料': Icons.water_drop_rounded,
    };
    for (final entry in expected.entries) {
      await _pump(tester, entry.key);
      expect(
        find.byIcon(entry.value),
        findsOneWidget,
        reason: '分类 ${entry.key} 应显示 ${entry.value}',
      );
    }
  });

  testWidgets('未知/空分类回落到通用餐具图标', (tester) async {
    await _pump(tester, '不存在的分类');
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    await _pump(tester, null);
    expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
  });

  testWidgets('水产用海产蓝调色,图标取分类 ink 色', (tester) async {
    await _pump(tester, '水产');
    final icon = tester.widget<Icon>(find.byIcon(Icons.set_meal_rounded));
    expect(icon.color, FkCategoryPalette.sea.ink);
  });
}
