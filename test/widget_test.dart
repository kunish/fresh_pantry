import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/widgets/dashboard/alert_card.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App smoke test - renders without crashing', (
    WidgetTester tester,
  ) async {
    // Provide a mock SharedPreferences for the test environment
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the app renders — the FreshPantryApp widget should exist
    expect(find.byType(FreshPantryApp), findsOneWidget);
  });

  testWidgets('custom expiry picker uses a Chinese date range dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 2),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expiry-range-picker')), findsOneWidget);
    expect(find.text('选择保质期范围'), findsOneWidget);
  });

  testWidgets(
    'custom expiry range picker keeps Chinese locale on English systems',
    (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            navigationProvider.overrideWith((ref) => 2),
          ],
          child: const FreshPantryApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      final dialogContext = tester.element(
        find.byKey(const Key('expiry-range-picker')),
      );
      expect(Localizations.localeOf(dialogContext), const Locale('zh', 'CN'));
    },
  );

  testWidgets(
    'custom expiry range picker keeps the system status bar visible',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            navigationProvider.overrideWith((ref) => 2),
          ],
          child: const FreshPantryApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('expiry-range-picker')),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnnotatedRegion<SystemUiOverlayStyle> &&
                widget.value.statusBarIconBrightness == Brightness.dark &&
                widget.value.statusBarBrightness == Brightness.light,
          ),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('custom expiry range picker omits combined range header', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 2),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('30天后'));
    await tester.tap(find.text('30天后'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());
    final end = today.add(const Duration(days: 30));

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(
      find.text('${_formatChineseDate(today)} - ${_formatChineseDate(end)}'),
      findsNothing,
    );
    expect(find.text(_formatChineseDate(today)), findsOneWidget);
    expect(find.text(_formatChineseDate(end)), findsOneWidget);
  });

  testWidgets('custom expiry range picker uses wheel date selection', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 2),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('expiry-start-date-tab')), findsOneWidget);
    expect(find.byKey(const Key('expiry-end-date-tab')), findsOneWidget);
    expect(find.byKey(const Key('expiry-date-wheel')), findsOneWidget);
    final picker = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(picker.minimumDate, isNull);
    expect(picker.maximumDate, isNull);
    expect(picker.minimumYear, lessThanOrEqualTo(DateTime.now().year));
    expect(picker.maximumYear, greaterThanOrEqualTo(DateTime.now().year));
    expect(find.byKey(const Key('expiry-year-selector')), findsNothing);
    expect(find.byKey(const Key('expiry-month-selector')), findsNothing);
  });

  testWidgets(
    'custom expiry wheel expands range instead of snapping to bounds',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
            navigationProvider.overrideWith((ref) => 2),
          ],
          child: const FreshPantryApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('30天后'));
      await tester.tap(find.text('30天后'));
      await tester.pumpAndSettle();

      final today = DateUtils.dateOnly(DateTime.now());
      final laterThanEnd = today.add(const Duration(days: 45));

      await tester.ensureVisible(find.text('自定义'));
      await tester.tap(find.text('自定义'));
      await tester.pumpAndSettle();

      tester
          .widget<CupertinoDatePicker>(find.byType(CupertinoDatePicker))
          .onDateTimeChanged(laterThanEnd);
      await tester.pumpAndSettle();

      expect(
        find.text(
          '${_formatChineseDate(laterThanEnd)} - '
          '${_formatChineseDate(laterThanEnd)}',
        ),
        findsNothing,
      );
      expect(find.text(_formatChineseDate(laterThanEnd)), findsNWidgets(2));
    },
  );

  testWidgets('expiration quick presets are labeled as days from now', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 2),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3天后'), findsOneWidget);
    expect(find.text('7天后'), findsOneWidget);
    expect(find.text('14天后'), findsOneWidget);
    expect(find.text('30天后'), findsOneWidget);
  });

  testWidgets(
    'dashboard expiring overview opens inventory with not fresh filter',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          _ingredient('黄瓜').toJson(),
          _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
        ]),
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();
      late ProviderContainer container;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
          child: Builder(
            builder: (context) {
              container = ProviderScope.containerOf(context);
              return const FreshPantryApp();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('即将过期').first);
      await tester.pumpAndSettle();

      expect(container.read(navigationProvider), 1);
      expect(container.read(selectedCategoryProvider), '不新鲜');
      expect(
        container.read(filteredByCategoryProvider).map((item) => item.name),
        ['牛奶'],
      );
    },
  );

  testWidgets('dashboard urgent attention shows every not fresh item', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('黄瓜').toJson(),
        _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
        _ingredient('面包', state: FreshnessState.expired).toJson(),
        _ingredient('番茄', state: FreshnessState.expiringSoon).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('牛奶')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('面包')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertCard), matching: find.text('番茄')),
      findsOneWidget,
    );
  });

  testWidgets(
    'dashboard urgent attention uses the item expiry label as badge',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          _ingredient(
            '面包',
            state: FreshnessState.expired,
          ).copyWith(expiryLabel: '已过期2天').toJson(),
        ]),
        'shopping_items': '[]',
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
          child: const FreshPantryApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已过期2天'), findsWidgets);
      expect(find.text('今天'), findsNothing);
      expect(find.text('48H'), findsNothing);
    },
  );

  testWidgets('alert cards keep actions visible on narrow dashboard widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: AlertCard(
                icon: Icons.kitchen,
                iconColor: Colors.green,
                name: '牛奶',
                subtitle: '已过期2天',
                storageTag: '冰箱',
                badge: '已过期2天',
                badgeBg: Colors.orange,
                badgeText: Colors.black,
                onConsume: () {},
                onAddToCart: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('已消耗'), findsOneWidget);
    expect(find.text('加入清单'), findsOneWidget);
    expect(find.text('已过期2天'), findsWidgets);
  });

  testWidgets('dashboard total overview resets inventory filter to all', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient('黄瓜').toJson(),
        _ingredient('牛奶', state: FreshnessState.expiringSoon).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          selectedCategoryProvider.overrideWith((ref) => '不新鲜'),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('种食材'));
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 1);
    expect(container.read(selectedCategoryProvider), '全部');
    expect(
      container.read(filteredByCategoryProvider).map((item) => item.name),
      ['黄瓜', '牛奶'],
    );
  });

  testWidgets('dashboard storage overview omits view all shortcut', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('存储概况'), findsOneWidget);
    expect(find.text('查看全部'), findsNothing);
  });

  testWidgets('custom expiry range picker starts on selected preset range', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 2),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('30天后'));
    await tester.tap(find.text('30天后'));
    await tester.pumpAndSettle();

    final today = DateUtils.dateOnly(DateTime.now());

    await tester.ensureVisible(find.text('自定义'));
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        '${_formatChineseDate(today)} - '
        '${_formatChineseDate(today.add(const Duration(days: 30)))}',
      ),
      findsNothing,
    );
    expect(find.text(_formatChineseDate(today)), findsOneWidget);
    expect(
      find.text(_formatChineseDate(today.add(const Duration(days: 30)))),
      findsOneWidget,
    );
  });

  testWidgets('discarding a new ingredient clears the form in place', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('库存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 2);
    expect(find.text('策划您的食材库'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, '牛奶');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, '牛奶'), findsOneWidget);

    await tester.ensureVisible(find.text('丢弃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('丢弃').last);
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 2);
    expect(find.text('策划您的食材库'), findsOneWidget);
    expect(find.widgetWithText(TextField, '牛奶'), findsNothing);
  });

  testWidgets('search inventory result resets selected inventory category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          '牛奶',
        ).copyWith(category: FoodCategories.dairyAndEggs).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            const _FakeFoodDetailsClient(null),
          ),
          selectedCategoryProvider.overrideWith(
            (ref) => inventoryFilterNotFresh,
          ),
        ],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return const FreshPantryApp();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '牛奶').first);
    await tester.pumpAndSettle();

    expect(container.read(navigationProvider), 1);
    expect(container.read(selectedCategoryProvider), inventoryFilterAll);
    expect(find.text('牛奶'), findsOneWidget);
  });

  testWidgets('top search shows online food details when local lists miss', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '有机全脂牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl:
          'data:image/png;base64,'
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/'
          'x8AAwMCAO+/p9sAAAAASUVORK5CYII=',
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('食材百科'), findsOneWidget);
    expect(find.text('有机全脂牛奶'), findsOneWidget);
    expect(find.textContaining('Open Food Facts 返回的牛奶详情'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.image is MemoryImage,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('有机全脂牛奶'));
    await tester.pumpAndSettle();

    expect(find.text('食材详情'), findsOneWidget);
    expect(find.text('分类：${FoodCategories.dairyAndEggs}'), findsOneWidget);
    expect(find.text('来源：Open Food Facts'), findsOneWidget);
  });

  testWidgets('top search summarizes generic online food details usefully', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '牛奶',
      description: 'Open Food Facts 记录的乳品蛋类食品。',
      imageUrl: null,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('食材百科'), findsOneWidget);
    expect(find.widgetWithText(ListTile, '牛奶'), findsOneWidget);
    expect(find.text('乳品蛋类 · 冰箱保存 · 约 7 天'), findsOneWidget);
    expect(find.textContaining('Open Food Facts 记录'), findsNothing);
    expect(find.textContaining('Open Food Facts'), findsNothing);
  });

  testWidgets('top search shows online food details alongside local matches', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([
        _ingredient(
          '牛奶',
        ).copyWith(category: FoodCategories.dairyAndEggs).toJson(),
      ]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    final details = FoodDetails(
      displayName: '有机全脂牛奶',
      description: 'Open Food Facts 返回的牛奶详情',
      imageUrl: null,
      category: FoodCategories.dairyAndEggs,
      storage: IconType.fridge,
      shelfLifeDays: 7,
      source: 'Open Food Facts',
      fetchedAt: DateTime.utc(2026, 5, 1),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          foodDetailsClientProvider.overrideWithValue(
            _FakeFoodDetailsClient(details),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
    await tester.pumpAndSettle();

    expect(find.text('库存食材'), findsOneWidget);
    expect(find.text('食材百科'), findsOneWidget);
    expect(find.text('有机全脂牛奶'), findsOneWidget);
  });

  testWidgets('search shopping result expands the matched category', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': jsonEncode([
        const ShoppingItem(
          id: 'tomato',
          name: '番茄',
          detail: '',
          category: FoodCategories.freshProduce,
        ).toJson(),
      ]),
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
          navigationProvider.overrideWith((ref) => 3),
          foodDetailsClientProvider.overrideWithValue(
            const _FakeFoodDetailsClient(null),
          ),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text(FoodCategories.freshProduce));
    await tester.pumpAndSettle();
    expect(find.text('番茄'), findsNothing);

    await tester.tap(find.byTooltip('搜索'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '番茄');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '番茄').first);
    await tester.pumpAndSettle();

    expect(find.text('番茄'), findsOneWidget);
  });
}

class _FakeFoodDetailsClient implements FoodDetailsClient {
  const _FakeFoodDetailsClient(this.details);

  final FoodDetails? details;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) async => details;
}

String _formatChineseDate(DateTime date) {
  return '${date.year}年${date.month}月${date.day}日';
}

Ingredient _ingredient(
  String name, {
  FreshnessState state = FreshnessState.fresh,
}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: state,
    category: '测试',
    storage: IconType.fridge,
    expiryLabel: state == FreshnessState.fresh ? '新鲜' : '即将过期',
  );
}
