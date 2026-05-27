import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:fresh_pantry/widgets/inventory/ingredient_card.dart';
import 'package:fresh_pantry/widgets/shared/cat_icon.dart';

void main() {
  testWidgets('ingredient card uses the category icon instead of imageUrl', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IngredientCard(
            ingredient: const Ingredient(
              name: '番茄',
              quantity: '2',
              unit: '个',
              imageUrl: 'https://example.com/tomato.jpg',
              freshnessPercent: 0.9,
              state: FreshnessState.fresh,
              category: FoodCategories.freshProduce,
              storage: IconType.fridge,
              expiryLabel: '新鲜',
            ),
          ),
        ),
      ),
    );

    expect(find.text('番茄'), findsOneWidget);
    // FK CatIcon (cartoon line SVG) replaced the old Material outlined icon.
    expect(find.byType(CatIcon), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('expiringSoon item shows expiry label with warning palette', (
    tester,
  ) async {
    const card = IngredientCard(
      ingredient: Ingredient(
        name: '牛奶',
        quantity: '1',
        unit: '盒',
        imageUrl: '',
        freshnessPercent: 0.2,
        state: FreshnessState.expiringSoon,
        category: FoodCategories.dairyAndEggs,
        storage: IconType.fridge,
        expiryLabel: '明天过期',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: card)),
    );

    // Badge text appears in upper case (TextStyle preserves the original
    // text, the badge widget uppercases it).
    expect(find.text('明天过期'.toUpperCase()), findsOneWidget);

    final badge = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('明天过期'.toUpperCase()),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = badge.decoration as BoxDecoration;
    expect(decoration.color, AppColors.secondaryContainer);
  });

  testWidgets('expired item shows expiry label with error palette', (
    tester,
  ) async {
    const card = IngredientCard(
      ingredient: Ingredient(
        name: '面包',
        quantity: '1',
        unit: '袋',
        imageUrl: '',
        freshnessPercent: 0.0,
        state: FreshnessState.expired,
        category: FoodCategories.other,
        storage: IconType.pantry,
        expiryLabel: '已过期2天',
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: card)),
    );

    expect(find.text('已过期2天'.toUpperCase()), findsOneWidget);

    final badge = tester.widget<Container>(
      find
          .ancestor(
            of: find.text('已过期2天'.toUpperCase()),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = badge.decoration as BoxDecoration;
    // FK redesign: expired status uses solid danger color (#E76F51), not its container.
    expect(decoration.color, AppColors.fkDanger);
  });
}
