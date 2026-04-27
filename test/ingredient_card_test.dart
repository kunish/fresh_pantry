import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/widgets/inventory/ingredient_card.dart';

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
    expect(find.byIcon(Icons.eco_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
