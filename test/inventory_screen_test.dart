import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/inventory_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'inventory screen does not show middle search or quick add inputs',
    (tester) async {
      SharedPreferences.setMockInitialValues({'inventory_items': '[]'});
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('快速添加'), findsNothing);
      expect(find.textContaining('搜索'), findsNothing);
      expect(find.text('不新鲜'), findsOneWidget);
      expect(
        find.ancestor(of: find.text('不新鲜'), matching: find.byType(ListView)),
        findsNothing,
      );
      expect(
        tester.getTopLeft(find.text('不新鲜')).dx,
        lessThan(tester.getTopLeft(find.text('全部')).dx),
      );
    },
  );

  testWidgets(
    'deletes the selected filtered inventory item by original index',
    (tester) async {
      final otherCategoryItem = _ingredient(
        name: '米饭',
        category: FoodCategories.other,
      );
      final targetCategoryItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      );
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          otherCategoryItem.toJson(),
          targetCategoryItem.toJson(),
        ]),
      });
      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: Scaffold(body: InventoryScreen()));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(FoodCategories.freshProduce));
      await tester.pumpAndSettle();

      await tester.tap(find.text('番茄'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除').last);
      await tester.pumpAndSettle();

      expect(container.read(inventoryProvider).map((item) => item.name), [
        '米饭',
      ]);
    },
  );

  testWidgets('swipe delete removes the selected duplicate-name item', (
    tester,
  ) async {
    final firstItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    ).copyWith(quantity: '1');
    final secondItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    ).copyWith(quantity: '2');
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([firstItem.toJson(), secondItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(
      find.byKey(const ValueKey('inv_swipe_番茄_1')),
      const Offset(-240, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inventory_swipe_delete_番茄_1')));
    await tester.pumpAndSettle();

    final items = container.read(inventoryProvider);
    expect(items, hasLength(1));
    expect(items.single.quantity, '1');
  });

  testWidgets('swiping an inventory item reveals delete without removing it', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('番茄'), const Offset(-240, 0));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).single.name, '番茄');
    expect(find.text('删除食材'), findsNothing);
    expect(
      find.byKey(const ValueKey('inventory_swipe_delete_番茄_0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('inventory_swipe_delete_番茄_0')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), isEmpty);
    expect(find.text('「番茄」已删除'), findsOneWidget);
  });

  testWidgets('delete snackbar with undo auto dismisses after timeout', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsNothing);
  });

  testWidgets('edit action opens form and updates selected inventory item', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([targetItem.toJson()]),
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();

    expect(find.text('编辑食材'), findsOneWidget);
    expect(find.widgetWithText(TextField, '番茄'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '番茄'), '樱桃番茄');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存修改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存修改'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).single.name, '樱桃番茄');
    expect(find.text('「樱桃番茄」已更新'), findsOneWidget);
  });
}

Ingredient _ingredient({required String name, required String category}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: category,
    storage: IconType.fridge,
    expiryLabel: '新鲜',
  );
}
