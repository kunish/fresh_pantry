import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';
import 'package:fresh_pantry/widgets/shared/category_icon.dart';
import 'package:fresh_pantry/widgets/shared/recipe_image.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));
Widget _wrapProvider(Widget child) =>
    ProviderScope(child: MaterialApp(home: Scaffold(body: child)));

void main() {
  // ── CategoryIcon helpers ──────────────────────────────────────────────────

  group('fkCategoryIdFor', () {
    test('maps dairyAndEggs to dairy', () {
      expect(fkCategoryIdFor(FoodCategories.dairyAndEggs), 'dairy');
    });

    test('maps freshProduce to veg', () {
      expect(fkCategoryIdFor(FoodCategories.freshProduce), 'veg');
    });

    test('maps meatAndSeafood to meat', () {
      expect(fkCategoryIdFor(FoodCategories.meatAndSeafood), 'meat');
    });

    test('maps herbsAndSpices to sauce', () {
      expect(fkCategoryIdFor(FoodCategories.herbsAndSpices), 'sauce');
    });

    test('maps other to grain', () {
      expect(fkCategoryIdFor(FoodCategories.other), 'grain');
    });

    test('maps null to grain (fallback)', () {
      expect(fkCategoryIdFor(null), 'grain');
    });
  });

  group('categoryIconFor', () {
    test('returns icon for each category', () {
      for (final cat in FoodCategories.values) {
        final icon = categoryIconFor(cat);
        expect(icon, isNotNull);
      }
    });
  });

  // ── RecipeImage ───────────────────────────────────────────────────────────

  group('RecipeImage', () {
    testWidgets('shows fallback when imageSource is null', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RecipeImage(imageSource: null, fallback: const Text('placeholder')),
        ),
      );
      await tester.pump();
      expect(find.text('placeholder'), findsOneWidget);
    });

    testWidgets('shows fallback when imageSource is empty string', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          RecipeImage(imageSource: '', fallback: const Text('empty-fallback')),
        ),
      );
      await tester.pump();
      expect(find.text('empty-fallback'), findsOneWidget);
    });
  });

  // ── BottomNavBar ──────────────────────────────────────────────────────────

  group('BottomNavBar', () {
    testWidgets('renders without error', (tester) async {
      await tester.pumpWidget(_wrapProvider(const BottomNavBar()));
      expect(find.byType(BottomNavBar), findsOneWidget);
    });

    testWidgets('tap switches the navigation provider tab', (tester) async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: BottomNavBar())),
        ),
      );

      await tester.tap(find.text('食材'));
      await tester.pump();

      expect(container.read(navigationProvider), FkTab.fridge);
    });
  });
}
