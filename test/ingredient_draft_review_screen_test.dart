import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/ingredient_draft.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ingredient_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<IngredientDraft> _stubs() => [
      IngredientDraft(
        id: '1',
        name: DraftField.ai('番茄'),
        quantity: DraftField.ai('3'),
        unit: DraftField.ai('个'),
        category: DraftField.ai('蔬菜'),
        storage: DraftField.ai(IconType.fridge),
        shelfLifeDays: DraftField.ai(7),
      ),
      IngredientDraft(
        id: '2',
        name: DraftField.ai('鸡蛋'),
        quantity: DraftField.ai('6'),
        unit: DraftField.ai('颗'),
        category: DraftField.ai('蛋奶'),
        storage: DraftField.ai(IconType.fridge),
        shelfLifeDays: DraftField.ai(30),
      ),
    ];

void main() {
  testWidgets('shows N rows, all selected, button label "入库 (2 项)"', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('入库 (2 项)'), findsOneWidget);
  });

  testWidgets('toggling a row updates the button count', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('ingredient_row_1')));
    await tester.pumpAndSettle();
    expect(find.text('入库 (1 项)'), findsOneWidget);
  });

  testWidgets('confirm writes selected to inventoryProvider and clears draft', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(aiDraftProvider.notifier).updateIngredientDrafts(_stubs());

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: IngredientDraftReviewScreen()),
    ));
    await tester.tap(find.byKey(const Key('ingredient_review_confirm')));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider).length, 2);
    expect(container.read(aiDraftProvider).ingredientDrafts, isNull);
  });
}
