import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/widgets/shopping/shopping_item_tile.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('shopping item tile hides quantity unit and source detail', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShoppingItemTile(
            item: const ShoppingItem(
              id: 'tomato',
              name: '有机传家宝番茄',
              detail: '4个 · 农贸市场',
              imageUrl: 'https://example.com/tomato.jpg',
              category: FoodCategories.freshProduce,
            ),
            onTap: () {},
          ),
        ),
      ),
    );

    expect(find.text('有机传家宝番茄'), findsOneWidget);
    expect(find.text('4个 · 农贸市场'), findsNothing);
    expect(find.byIcon(Icons.eco_outlined), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
