# Interaction Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make small, focused fixes so inventory, shopping, search, expiry labels, and add-form feedback behave consistently.

**Architecture:** Keep the existing Riverpod notifiers and screen structure. Add minimal provider methods for operations that need precise state semantics, then update UI call sites to consume existing return values and reset navigation/filter state deliberately.

**Tech Stack:** Flutter, Dart, Riverpod Notifier/StateProvider, SharedPreferences, Flutter widget tests.

---

## File Structure

- Modify `lib/providers/inventory_provider.dart` to expose shared expiry labeling and inventory insertion/removal methods that do not pollute add history.
- Modify `lib/providers/shopping_provider.dart` only if batch shopping behavior needs a single source of truth; prefer existing `add()` return value.
- Modify `lib/screens/add_ingredient_screen.dart` to use robust undo, edit-by-original-item lookup, stale image protection, and shared expiry labels.
- Modify `lib/screens/batch_entry_screen.dart` to use shared expiry labels.
- Modify `lib/screens/dashboard_screen.dart` to surface add-to-cart duplicate feedback and use real expiry labels in urgent attention.
- Modify `lib/screens/inventory_screen.dart` to show duplicate add feedback and restore inventory deletions at their original index.
- Modify `lib/screens/shopping_list_screen.dart` to expose category expansion and show accurate inventory-add feedback.
- Modify `lib/widgets/common/search_overlay.dart` to reset inventory filters and expand shopping categories when navigating from search results.
- Modify tests under `test/` to prove each behavior before implementation.

## Task 1: Inventory State Semantics

**Files:**
- Modify: `lib/providers/inventory_provider.dart`
- Test: `test/provider_logic_test.dart`

- [ ] **Step 1: Write failing provider tests**

Add tests that prove reinserting an existing inventory item preserves position and does not increment add history, and that shared expiry labels handle expired, today, tomorrow, and future dates.

```dart
test('inserts inventory item at the requested index without recording add history', () async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': json.encode([
      _ingredient('牛奶').toJson(),
      _ingredient('番茄').toJson(),
    ]),
    'add_history': json.encode({
      '鸡蛋': {'count': 1, 'category': '蛋类', 'storage': 'fridge', 'unit': '个'},
    }),
  });
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  await container.read(inventoryProvider.notifier).insertAt(1, _ingredient('鸡蛋'));

  expect(container.read(inventoryProvider).map((item) => item.name), ['牛奶', '鸡蛋', '番茄']);
  final history = json.decode(prefs.getString('add_history')!);
  expect(history['鸡蛋']['count'], 1);
});

test('formats expiry labels consistently', () {
  final now = DateTime(2026, 4, 27, 14);

  expect(expiryLabelFor(DateTime(2026, 4, 26), now: now), '已过期1天');
  expect(expiryLabelFor(DateTime(2026, 4, 27), now: now), '今天过期');
  expect(expiryLabelFor(DateTime(2026, 4, 28), now: now), '明天过期');
  expect(expiryLabelFor(DateTime(2026, 5, 1), now: now), '4天后过期');
});
```

- [ ] **Step 2: Run failing tests**

Run: `flutter test test/provider_logic_test.dart`

Expected: FAIL because `insertAt` and public `expiryLabelFor` do not exist yet.

- [ ] **Step 3: Implement provider methods**

In `lib/providers/inventory_provider.dart`, rename private `_expiryLabelFor` to public `expiryLabelFor`, update internal callers, and add an insertion method.

```dart
String expiryLabelFor(DateTime expiryDate, {DateTime? now}) {
  final days = daysUntilExpiry(expiryDate, now: now);
  if (days < 0) return '已过期${-days}天';
  if (days == 0) return '今天过期';
  if (days == 1) return '明天过期';
  return '$days天后过期';
}

Future<void> insertAt(int index, Ingredient item) async {
  final normalizedItem = _normalizeInventoryIngredient(item);
  final clampedIndex = index.clamp(0, state.length);
  final updated = [...state]..insert(clampedIndex, normalizedItem);
  state = updated;
  return _queuePersistence(() => _save(updated));
}
```

- [ ] **Step 4: Verify provider tests pass**

Run: `flutter test test/provider_logic_test.dart`

Expected: PASS.

## Task 2: Add Ingredient Flow Consistency

**Files:**
- Modify: `lib/screens/add_ingredient_screen.dart`
- Test: `test/add_ingredient_screen_test.dart`, `test/widget_test.dart`

- [ ] **Step 1: Write failing widget tests**

Add tests for save undo removing only the newly added item when duplicate names exist, and for stale image lookups not overwriting a changed name.

```dart
testWidgets('undo after adding duplicate name removes the newly added item only', (tester) async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': jsonEncode([_ingredient('牛奶').copyWith(quantity: '1').toJson()]),
    'shopping_items': '[]',
    'add_history': '{}',
  });
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: Builder(
        builder: (context) {
          container = ProviderScope.containerOf(context);
          return MaterialApp(theme: AppTheme.lightTheme, home: const Scaffold(body: AddIngredientScreen()));
        },
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.enterText(find.byType(TextField).first, '牛奶');
  await tester.ensureVisible(find.text('保存'));
  await tester.tap(find.text('保存'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('撤销'));
  await tester.pumpAndSettle();

  expect(container.read(inventoryProvider).map((item) => item.quantity), ['1']);
});
```

- [ ] **Step 2: Run failing add-flow tests**

Run: `flutter test test/add_ingredient_screen_test.dart test/widget_test.dart`

Expected: FAIL on the new undo scenario before code changes.

- [ ] **Step 3: Implement robust add/edit/image behavior**

In `AddIngredientScreen`, use shared `expiryLabelFor`, remove stale image results, and undo by object identity.

```dart
Future<void> _lookupImage(String name) async {
  if (name.length < 2) return;
  try {
    final result = await OpenFoodFactsService.searchByName(name);
    if (!mounted || _nameController.text.trim() != name) return;
    setState(() => _resolvedImageUrl = result?.imageUrl ?? '');
  } catch (_) {}
}

final itemToAdd = ingredient;
ref.read(inventoryProvider.notifier).add(itemToAdd);

onPressed: () {
  final index = inventoryIndexOf(ref.read(inventoryProvider), itemToAdd);
  if (index != -1) {
    ref.read(inventoryProvider.notifier).remove(index);
  }
}
```

For edit save, recompute the current index from `widget.initialIngredient!` before update.

```dart
final index = inventoryIndexOf(ref.read(inventoryProvider), widget.initialIngredient!);
if (index == -1) {
  Navigator.of(context).pop();
  return;
}
ref.read(inventoryProvider.notifier).update(index, ingredient);
```

- [ ] **Step 4: Verify add-flow tests pass**

Run: `flutter test test/add_ingredient_screen_test.dart test/widget_test.dart`

Expected: PASS.

## Task 3: Shopping Add Feedback And Undo Consistency

**Files:**
- Modify: `lib/screens/inventory_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart`
- Modify: `lib/screens/recipe_detail_screen.dart`
- Modify: `lib/screens/shopping_list_screen.dart`
- Test: `test/inventory_screen_test.dart`, `test/shopping_list_screen_test.dart`, `test/widget_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests that duplicate add-to-cart actions show duplicate feedback, deletion undo restores original position, and recipe missing-ingredient add reports the actual number added.

```dart
testWidgets('shopping duplicate feedback is shown from inventory buy again', (tester) async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': jsonEncode([_ingredient('牛奶').toJson()]),
    'shopping_items': jsonEncode([const ShoppingItem(id: 'milk', name: '牛奶', detail: '', category: FoodCategories.dairyAndEggs).toJson()]),
    'add_history': '{}',
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: Scaffold(body: InventoryScreen())),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text('再次购买'));
  await tester.pumpAndSettle();

  expect(find.text('「牛奶」已在购物清单中'), findsOneWidget);
});
```

- [ ] **Step 2: Run failing interaction tests**

Run: `flutter test test/inventory_screen_test.dart test/shopping_list_screen_test.dart test/widget_test.dart`

Expected: FAIL on the new duplicate feedback or undo assertions.

- [ ] **Step 3: Implement shared add result handling at call sites**

At each `shoppingProvider.notifier.add(...)` call site, await or handle the returned bool and show feedback from that result.

```dart
final added = await ref.read(shoppingProvider.notifier).add(item);
ScaffoldMessenger.of(context).clearSnackBars();
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中'),
    persist: false,
    backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
);
```

For inventory delete undo, store the original index and use `insertAt`.

```dart
final index = _indexOfInventoryItem(item);
ref.read(inventoryProvider.notifier).remove(index);
...
onPressed: () {
  ref.read(inventoryProvider.notifier).insertAt(index, item);
}
```

- [ ] **Step 4: Verify shopping interaction tests pass**

Run: `flutter test test/inventory_screen_test.dart test/shopping_list_screen_test.dart test/widget_test.dart`

Expected: PASS.

## Task 4: Search Navigation And Category Visibility

**Files:**
- Modify: `lib/screens/shopping_list_screen.dart`
- Modify: `lib/widgets/common/search_overlay.dart`
- Test: `test/widget_test.dart`

- [ ] **Step 1: Write failing search navigation tests**

Add tests that search inventory results reset the inventory filter and that shopping search results expand a collapsed category.

```dart
testWidgets('search inventory result resets selected inventory category', (tester) async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': jsonEncode([_ingredient('牛奶').copyWith(category: FoodCategories.dairyAndEggs).toJson()]),
    'shopping_items': '[]',
    'add_history': '{}',
  });
  final prefs = await SharedPreferences.getInstance();
  late ProviderContainer container;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs), selectedCategoryProvider.overrideWith((ref) => inventoryFilterNotFresh)],
      child: Builder(builder: (context) {
        container = ProviderScope.containerOf(context);
        return const FreshPantryApp();
      }),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.byTooltip('搜索'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, '搜索食材...'), '牛奶');
  await tester.pumpAndSettle();
  await tester.tap(find.text('牛奶').last);
  await tester.pumpAndSettle();

  expect(container.read(navigationProvider), 1);
  expect(container.read(selectedCategoryProvider), inventoryFilterAll);
});
```

- [ ] **Step 2: Run failing search tests**

Run: `flutter test test/widget_test.dart`

Expected: FAIL before search navigation updates filters.

- [ ] **Step 3: Implement navigation resets and expansion hook**

Add a provider for expanded shopping category requests.

```dart
final shoppingCategoryToExpandProvider = StateProvider<String?>((ref) => null);
```

In `SearchOverlay`, reset inventory filters and request shopping expansion before navigation.

```dart
ref.read(selectedCategoryProvider.notifier).state = inventoryFilterAll;
ref.navigateToTab(1);

ref.read(shoppingCategoryToExpandProvider.notifier).state = item.category;
ref.navigateToTab(3);
```

In `ShoppingListScreen`, listen and remove the requested category from `_collapsedCategories`.

```dart
ref.listen<String?>(shoppingCategoryToExpandProvider, (previous, category) {
  if (category == null) return;
  if (_collapsedCategories.remove(category)) {
    setState(() {});
  }
  ref.read(shoppingCategoryToExpandProvider.notifier).state = null;
});
```

- [ ] **Step 4: Verify search tests pass**

Run: `flutter test test/widget_test.dart`

Expected: PASS.

## Task 5: Expiry Label And Batch Consistency

**Files:**
- Modify: `lib/screens/batch_entry_screen.dart`
- Modify: `lib/screens/dashboard_screen.dart`
- Test: `test/provider_logic_test.dart`, `test/widget_test.dart`

- [ ] **Step 1: Write failing tests**

Add tests for batch-created expiry labels and dashboard urgent attention showing the real expiry label instead of hardcoded badges.

```dart
testWidgets('urgent attention uses the item expiry label as the badge', (tester) async {
  SharedPreferences.setMockInitialValues({
    'inventory_items': jsonEncode([
      _ingredient('面包', state: FreshnessState.expired).copyWith(expiryLabel: '已过期2天').toJson(),
    ]),
    'shopping_items': '[]',
    'add_history': '{}',
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const FreshPantryApp(),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('已过期2天'), findsWidgets);
  expect(find.text('48H'), findsNothing);
});
```

- [ ] **Step 2: Run failing expiry tests**

Run: `flutter test test/provider_logic_test.dart test/widget_test.dart`

Expected: FAIL for hardcoded dashboard badge before implementation.

- [ ] **Step 3: Use shared expiry labels**

In batch entry and dashboard, use `expiryLabelFor` or the item's existing `expiryLabel`.

```dart
expiryLabel: item.expiryDate != null ? expiryLabelFor(item.expiryDate!) : '新鲜',
```

```dart
badge: e.value.expiryLabel ?? '即将过期',
```

- [ ] **Step 4: Verify expiry tests pass**

Run: `flutter test test/provider_logic_test.dart test/widget_test.dart`

Expected: PASS.

## Task 6: Full Verification

**Files:**
- No new files beyond the implementation above.

- [ ] **Step 1: Run focused tests**

Run: `flutter test test/provider_logic_test.dart test/add_ingredient_screen_test.dart test/inventory_screen_test.dart test/shopping_list_screen_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 2: Run full test suite**

Run: `flutter test`

Expected: PASS.

- [ ] **Step 3: Run analyzer**

Run: `flutter analyze`

Expected: No issues found.

- [ ] **Step 4: Do not commit unless requested**

Leave changes unstaged unless the user explicitly asks for a commit.

## Self-Review

- Spec coverage: The plan covers add feedback, search visibility, undo semantics, expiry labels, stale image results, and test verification.
- Placeholder scan: No open implementation placeholders remain; every task has concrete files, commands, and target code shape.
- Type consistency: New public functions are `expiryLabelFor` and `InventoryNotifier.insertAt`; new provider is `shoppingCategoryToExpandProvider` with type `StateProvider<String?>`.
