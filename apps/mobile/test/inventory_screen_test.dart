import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ingredient_detail_screen.dart';
import 'package:fresh_pantry/screens/inventory_screen.dart';
import 'package:fresh_pantry/widgets/inventory/ingredient_card.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('inventory FK chrome: top bar + search + chips + 2-col grid', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(
                name: '牛奶',
                category: FoodCategories.dairyAndEggs,
              ).copyWith(state: FreshnessState.expiringSoon),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // FkTopBar header + 共 N 件 subtitle.
    expect(find.text('我的食材'), findsOneWidget);
    expect(find.text('共 2 件'), findsOneWidget);

    // Search field is present (FK redesign adds it inline).
    final searchHint = find.text('搜索食材');
    expect(searchHint, findsOneWidget);

    // Filter chips: "全部 · 2" + the 不新鲜 status chip with its count.
    expect(find.text('全部 · 2'), findsOneWidget);
    expect(find.text('不新鲜 · 1'), findsOneWidget);

    // Search by name narrows the visible cards.
    await tester.enterText(find.widgetWithText(TextField, '搜索食材'), '番茄');
    await tester.pumpAndSettle();
    // 番茄 is now visible both in the search field text and the card name.
    expect(find.widgetWithText(IngredientCard, '番茄'), findsOneWidget);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsNothing);
  });

  test('reload re-reads persisted inventory instead of emptying it '
      '(pull-to-refresh regression)', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: testStorageOverrides(database: db),
    );
    addTearDown(container.dispose);

    final notifier = container.read(inventoryProvider.notifier);
    // Persist rows the way startup/sync does, so disk and state agree.
    await notifier.replaceFromRemote([
      _ingredient(name: '番茄', category: FoodCategories.freshProduce),
      _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
    ]);
    expect(container.read(inventoryProvider), hasLength(2));

    // The old pull-to-refresh ref.invalidate'd inventoryProvider, but
    // build() returns a one-shot startup seed that's already consumed → it
    // fell back to an empty list. reload() must re-read the persisted rows.
    await notifier.reload();

    expect(container.read(inventoryProvider).map((i) => i.name).toSet(), {
      '番茄',
      '牛奶',
    });
  });

  testWidgets('pull-to-refresh keeps the inventory instead of clearing it', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Persist rows so disk matches what the user sees (mirrors startup/sync).
    await container.read(inventoryProvider.notifier).replaceFromRemote([
      _ingredient(name: '番茄', category: FoodCategories.freshProduce),
      _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
    ]);
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IngredientCard, '番茄'), findsOneWidget);

    // Pull to refresh: drag the scroll view down far enough to trip onRefresh.
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1200,
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(IngredientCard, '番茄'), findsOneWidget);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsOneWidget);
  });

  testWidgets('clear-all button wipes the inventory after confirmation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), hasLength(2));

    await tester.tap(find.byKey(const Key('inventory_clear_all_button')));
    await tester.pumpAndSettle();

    // Confirmation dialog appears before anything is deleted.
    expect(find.text('清空'), findsOneWidget);
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), isEmpty);
    expect(find.widgetWithText(IngredientCard, '番茄'), findsNothing);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsNothing);
    expect(find.text('该分类下暂无食材'), findsOneWidget);
  });

  testWidgets('clear-all button is hidden when the inventory is empty', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory_clear_all_button')), findsNothing);
  });

  testWidgets('deletes the selected filtered inventory item by original index', (
    tester,
  ) async {
    final otherCategoryItem = _ingredient(
      name: '米饭',
      category: FoodCategories.other,
    );
    final targetCategoryItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [otherCategoryItem, targetCategoryItem],
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // FK chip text now shows "果蔬生鲜 · 1" — match by prefix.
    await tester.tap(find.textContaining(FoodCategories.freshProduce));
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    // Delete via the hero icon button, then pick 扔了 in the departure sheet.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('departure-wasted')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).map((item) => item.name), ['米饭']);
  });

  testWidgets(
    'detail delete removes the correct duplicate-name inventory item',
    (tester) async {
      final firstItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      ).copyWith(quantity: '1');
      final secondItem = _ingredient(
        name: '番茄',
        category: FoodCategories.freshProduce,
      ).copyWith(quantity: '2');
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(
              database: db,
              inventory: [firstItem, secondItem],
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const MaterialApp(home: Scaffold(body: InventoryScreen()));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FK redesign: each card is keyed by inv_<name>_<index>. Tap the
      // second duplicate to open detail.
      await tester.tap(find.byKey(const ValueKey('inv_番茄_1')));
      await tester.pumpAndSettle();

      // Delete via the hero icon button, then pick 扔了 in the departure sheet.
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('departure-wasted')));
      await tester.pumpAndSettle();

      final items = container.read(inventoryProvider);
      expect(items, hasLength(1));
      expect(items.single.quantity, '1');
    },
  );

  testWidgets('tapping an inventory card opens food details', (tester) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: [targetItem]),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(
              FoodDetails(
                displayName: '番茄',
                description: '多汁的果蔬生鲜食材',
                imageUrl: '',
                category: FoodCategories.freshProduce,
                storage: IconType.fridge,
                shelfLifeDays: 7,
                source: '本地食材知识库',
                fetchedAt: DateTime.utc(2026, 5, 1),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();

    // FK redesign: AppBar gone; hero shows display name + description card +
    // info-list rows ("分类|存放位置|保质期建议|来源" → "value").
    expect(find.text('多汁的果蔬生鲜食材'), findsOneWidget);
    expect(find.text('保质期建议'), findsOneWidget);
    expect(find.text('7天'), findsOneWidget);
    expect(find.text('本地食材知识库'), findsOneWidget);
    // Name appears in the hero — at least one instance must exist on screen.
    expect(find.text('番茄'), findsAtLeastNWidgets(1));
  });

  testWidgets('changing search after multi-select does not crash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('inv_番茄_1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '搜索食材'), '牛奶');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('已选 1 件'), findsNothing);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsOneWidget);
  });

  testWidgets(
    'ingredient detail hides inventory-only actions for online result',
    (tester) async {
      final onlineItem = _ingredient(
        name: '牛奶',
        category: FoodCategories.dairyAndEggs,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
            foodDetailsClientProvider.overrideWithValue(
              _FakeFoodDetailsClient(
                FoodDetails(
                  displayName: '牛奶',
                  description: '乳品蛋类食材',
                  imageUrl: null,
                  category: FoodCategories.dairyAndEggs,
                  storage: IconType.fridge,
                  shelfLifeDays: 7,
                  source: 'Open Food Facts',
                  fetchedAt: DateTime.utc(2026, 5, 1),
                ),
              ),
            ),
          ],
          child: MaterialApp(
            home: IngredientDetailScreen(ingredient: onlineItem),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // FK redesign: action button reads "加入清单"; edit/delete are icon-only
      // and only render when the item is in inventory (this one is not).
      expect(find.text('加入清单'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
    },
  );

  testWidgets('delete snackbar with undo auto dismisses after timeout', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: [targetItem]),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    // Delete via the hero icon button, then pick 扔了 in the departure sheet.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('departure-wasted')));
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('「番茄」已删除'), findsNothing);
  });

  testWidgets('delete undo restores the original inventory position', (
    tester,
  ) async {
    final firstItem = _ingredient(
      name: '牛奶',
      category: FoodCategories.dairyAndEggs,
    );
    final secondItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    final thirdItem = _ingredient(name: '米饭', category: FoodCategories.other);
    SharedPreferences.setMockInitialValues({
      'add_history': jsonEncode({
        '番茄': {
          'count': 1,
          'category': FoodCategories.freshProduce,
          'storage': 'fridge',
          'unit': '份',
        },
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [firstItem, secondItem, thirdItem],
          ),
        ],
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
    // Delete via the hero icon button, then pick 扔了 in the departure sheet.
    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('departure-wasted')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).map((item) => item.name), [
      '牛奶',
      '番茄',
      '米饭',
    ]);
    final history = jsonDecode(prefs.getString('add_history')!);
    expect(history['番茄']['count'], 1);
  });

  testWidgets('buy again reports duplicate shopping items', (tester) async {
    final targetItem = _ingredient(
      name: '牛奶',
      category: FoodCategories.dairyAndEggs,
    ).copyWith(state: FreshnessState.expiringSoon, expiryLabel: '明天过期');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [targetItem],
            shopping: const [
              ShoppingItem(
                id: 'milk',
                name: '牛奶',
                detail: '',
                category: FoodCategories.dairyAndEggs,
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // FK redesign relabels the inline buy-again CTA to "加购".
    await tester.tap(find.text('加购'));
    await tester.pumpAndSettle();

    expect(find.text('「牛奶」已在购物清单中'), findsOneWidget);
  });

  testWidgets('edit action opens form and updates selected inventory item', (
    tester,
  ) async {
    final targetItem = _ingredient(
      name: '番茄',
      category: FoodCategories.freshProduce,
    );
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: [targetItem]),
        ],
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
    // FK redesign: edit is an icon button on the hero.
    await tester.tap(find.byIcon(Icons.edit_outlined));
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

  testWidgets('multi-select exposes batch delete and add-to-shopping actions', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('inv_番茄_0')));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 件'), findsOneWidget);
    expect(
      find.byKey(const Key('inventory_selection_delete_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('inventory_selection_add_to_shopping_button')),
      findsOneWidget,
    );
  });

  testWidgets('batch delete removes the selected items and undo restores them', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
              _ingredient(name: '米饭', category: FoodCategories.other),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select the first and third item (non-adjacent, to exercise indexing).
    await tester.longPress(find.byKey(const ValueKey('inv_番茄_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inv_米饭_2')));
    await tester.pumpAndSettle();
    expect(find.text('已选 2 件'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory_selection_delete_button')));
    await tester.pumpAndSettle();
    // Departure sheet asks how the batch left inventory.
    await tester.tap(find.byKey(const ValueKey('departure-wasted')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).map((e) => e.name), ['牛奶']);
    expect(find.text('已删除 2 件食材'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).map((e) => e.name), [
      '番茄',
      '牛奶',
      '米饭',
    ]);
  });

  testWidgets('batch add-to-shopping pushes the selected items onto the list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(name: '牛奶', category: FoodCategories.dairyAndEggs),
            ],
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const MaterialApp(home: Scaffold(body: InventoryScreen()));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('inv_番茄_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inv_牛奶_1')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('inventory_selection_add_to_shopping_button')),
    );
    await tester.pumpAndSettle();

    expect(container.read(shoppingProvider).map((e) => e.name).toSet(), {
      '番茄',
      '牛奶',
    });
    expect(find.text('已添加 2 项到购物清单'), findsOneWidget);
    // Selection clears after the action completes.
    expect(find.text('已选 2 件'), findsNothing);
  });

  testWidgets('storage chips filter the grid by area with live counts', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(
                name: '冰淇淋',
                category: FoodCategories.other,
              ).copyWith(storage: IconType.freezer),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Default 全部位置: both areas' items are visible, chips carry counts.
    expect(find.widgetWithText(IngredientCard, '番茄'), findsOneWidget);
    expect(find.widgetWithText(IngredientCard, '冰淇淋'), findsOneWidget);
    expect(find.text('全部位置 · 2'), findsOneWidget);
    expect(find.text('冷冻室 · 1'), findsOneWidget);

    // Tap 冷冻室: only the frozen item remains.
    await tester.tap(find.text('冷冻室 · 1'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(IngredientCard, '番茄'), findsNothing);
    expect(find.widgetWithText(IngredientCard, '冰淇淋'), findsOneWidget);
  });

  testWidgets('changing the storage filter drops the multi-select', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(name: '番茄', category: FoodCategories.freshProduce),
              _ingredient(
                name: '冰淇淋',
                category: FoodCategories.other,
              ).copyWith(storage: IconType.freezer),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('inv_番茄_0')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 件'), findsOneWidget);

    // Switching storage reorders the display list, so the positional selection
    // must be dropped rather than silently pointing at a different row.
    await tester.tap(find.text('冷冻室 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 件'), findsNothing);
    expect(find.widgetWithText(IngredientCard, '冰淇淋'), findsOneWidget);
  });

  testWidgets('临期优先 toggle reorders the grid by soonest expiry', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(
                name: '番茄',
                category: FoodCategories.freshProduce,
              ).copyWith(expiryDate: DateTime(2026, 12, 20)),
              _ingredient(
                name: '牛奶',
                category: FoodCategories.dairyAndEggs,
              ).copyWith(expiryDate: DateTime(2026, 12, 8)),
              _ingredient(name: '盐', category: FoodCategories.other),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Default order is insertion order: 番茄 sits at display index 0.
    expect(find.byKey(const ValueKey('inv_番茄_0')), findsOneWidget);

    // Sort by expiry: soonest first (牛奶), then 番茄, with the no-expiry 盐 last.
    await tester.tap(find.byKey(const Key('inventory_sort_expiry_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inv_牛奶_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('inv_番茄_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('inv_盐_2')), findsOneWidget);

    // Toggle off: insertion order is restored.
    await tester.tap(find.byKey(const Key('inventory_sort_expiry_toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('inv_番茄_0')), findsOneWidget);
  });

  testWidgets('changing the sort order drops the multi-select', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(
                name: '番茄',
                category: FoodCategories.freshProduce,
              ).copyWith(expiryDate: DateTime(2026, 12, 20)),
              _ingredient(
                name: '牛奶',
                category: FoodCategories.dairyAndEggs,
              ).copyWith(expiryDate: DateTime(2026, 12, 8)),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('inv_番茄_0')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 件'), findsOneWidget);

    // Sorting reorders the display list, so the positional selection must drop
    // rather than silently point at a different row (filterKey invariant).
    await tester.tap(find.byKey(const Key('inventory_sort_expiry_toggle')));
    await tester.pumpAndSettle();
    expect(find.text('已选 1 件'), findsNothing);
  });

  testWidgets('expiry sort orders within the active category filter', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: [
              _ingredient(
                name: '番茄',
                category: FoodCategories.freshProduce,
              ).copyWith(expiryDate: DateTime(2026, 12, 20)),
              _ingredient(
                name: '香蕉',
                category: FoodCategories.freshProduce,
              ).copyWith(expiryDate: DateTime(2026, 12, 5)),
              // Soonest expiry overall, but a different category — must stay out
              // of the sorted result, proving sort runs on the filtered subset.
              _ingredient(
                name: '牛奶',
                category: FoodCategories.dairyAndEggs,
              ).copyWith(expiryDate: DateTime(2026, 12, 1)),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
      ),
    );
    await tester.pumpAndSettle();

    // Narrow to 果蔬生鲜 (2 items), then sort by expiry.
    await tester.tap(find.text('${FoodCategories.freshProduce} · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory_sort_expiry_toggle')));
    await tester.pumpAndSettle();

    // Within the category: 香蕉 (Dec 5) before 番茄 (Dec 20); 牛奶 stays filtered out.
    expect(find.byKey(const ValueKey('inv_香蕉_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('inv_番茄_1')), findsOneWidget);
    expect(find.widgetWithText(IngredientCard, '牛奶'), findsNothing);
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

class _FakeFoodDetailsClient implements FoodDetailsClient {
  _FakeFoodDetailsClient(this.details);

  final FoodDetails details;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) async => details;
}
