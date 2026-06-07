import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:fresh_pantry/utils/page_transitions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('add ingredient save shows missing field prompt', (tester) async {
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
            return MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: AddIngredientScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存前请补充：食材名称'), findsOneWidget);
    expect(container.read(inventoryProvider), isEmpty);
  });

  testWidgets('add undo removes the added item even after list changes', (
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
            inventory: [_ingredient('旧食材')],
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: AddIngredientScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '临时食材');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await container.read(inventoryProvider.notifier).remove(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), isEmpty);
  });

  testWidgets(
    'edit save updates the provided inventory index for equal items',
    (tester) async {
      // A perishable category so the two identical-name rows legitimately
      // coexist as separate batches — non-perishables now auto-merge on load,
      // which would otherwise collapse the pair this test relies on.
      final duplicateItem = _ingredient('重复食材').copyWith(category: '乳品蛋类');
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
              inventory: [duplicateItem, duplicateItem],
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(
                  body: AddIngredientScreen(
                    initialIngredient: duplicateItem,
                    inventoryIndex: 1,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '重复食材'), '第二份食材');
      await tester.ensureVisible(find.text('保存修改'));
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      final items = container.read(inventoryProvider);
      expect(items.map((item) => item.name), ['重复食材', '第二份食材']);
    },
  );

  testWidgets(
    'edit save reports stale inventory item instead of overwriting another row',
    (tester) async {
      final originalItem = _ingredient('原食材');
      final replacementItem = _ingredient('替代食材');
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
              inventory: [originalItem],
            ),
          ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return MaterialApp(
                theme: AppTheme.lightTheme,
                home: Scaffold(
                  body: AddIngredientScreen(
                    initialIngredient: originalItem,
                    inventoryIndex: 0,
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await container.read(inventoryProvider.notifier).remove(0);
      await container.read(inventoryProvider.notifier).add(replacementItem);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, '原食材'), '错误更新');
      await tester.ensureVisible(find.text('保存修改'));
      await tester.tap(find.text('保存修改'));
      await tester.pumpAndSettle();

      final items = container.read(inventoryProvider);
      expect(items.map((item) => item.name), ['替代食材']);
      expect(find.text('食材已不在库存中，无法保存修改'), findsOneWidget);
    },
  );

  testWidgets('edit cancel pops back to caller when form is unchanged', (
    tester,
  ) async {
    await _pumpEditScreenBehindHome(tester, _ingredient('番茄'));

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑食材'), findsOneWidget);

    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // Unchanged form must pop straight back — no discard dialog.
    expect(find.text('编辑食材'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
  });

  testWidgets('edit cancel discards changes and pops back without a dialog', (
    tester,
  ) async {
    await _pumpEditScreenBehindHome(tester, _ingredient('番茄'));

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '番茄'), '黄瓜');
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 取消即放弃未保存修改、直接返回 —— 不再弹「丢弃」确认对话框。
    expect(find.text('丢弃'), findsNothing);
    expect(find.text('编辑食材'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
  });

  testWidgets('edit screen pops back via the left-edge swipe gesture', (
    tester,
  ) async {
    await _pumpEditScreenBehindHome(tester, _ingredient('番茄'));

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑食材'), findsOneWidget);

    // 从左边缘分多步水平拖动(模拟真实滑动,让 back-gesture 稳定赢得手势竞技场),
    // 越过屏幕一半后松手,应直接返回上一页(放弃未保存修改)。
    final gesture = await tester.startGesture(const Offset(5, 300));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.text('编辑食材'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
  });

  testWidgets('edit screen shows a back arrow that pops', (tester) async {
    await _pumpEditScreenBehindHome(tester, _ingredient('番茄'));

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑食材'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();

    expect(find.text('编辑食材'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
  });
}

/// Pumps a home screen whose button pushes the edit form exactly the way
/// `IngredientDetailScreen._editItem` does (no AppBar, behind a route), so the
/// only way back out is the form's own cancel / system-back handling.
Future<void> _pumpEditScreenBehindHome(
  WidgetTester tester,
  Ingredient item,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db, inventory: [item]),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  fkRoute<void>(
                    builder: (_) => Scaffold(
                      body: SafeArea(
                        child: AddIngredientScreen(
                          initialIngredient: item,
                          inventoryIndex: 0,
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('打开编辑'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Ingredient _ingredient(String name) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: '测试',
    storage: IconType.fridge,
  );
}
