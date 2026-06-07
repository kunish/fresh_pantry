import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/recipe_detail_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

Recipe _recipe() => Recipe(
  id: 'r1',
  name: '红烧肉',
  category: '中餐',
  difficulty: 3,
  cookingMinutes: 40,
  description: '',
  ingredients: [
    RecipeIngredient(name: '五花肉', quantity: '300', unit: 'g'),
    RecipeIngredient(name: '盐', quantity: '', unit: '适量'),
  ],
  steps: const [],
);

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = newTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db, inventory: const []),
      ],
      child: MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: RecipeDetailScreen(recipe: _recipe()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('doubling the portion doubles a numeric ingredient amount', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('300g'), findsOneWidget);

    await tester.tap(find.text('2×'));
    await tester.pumpAndSettle();

    expect(find.text('600g'), findsOneWidget);
    expect(find.text('300g'), findsNothing);
    // A non-numeric "适量" must stay untouched at any scale.
    expect(find.text('适量'), findsOneWidget);
  });

  testWidgets('returning to 1× restores the original amount', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('3×'));
    await tester.pumpAndSettle();
    expect(find.text('900g'), findsOneWidget);

    await tester.tap(find.text('1×'));
    await tester.pumpAndSettle();
    expect(find.text('300g'), findsOneWidget);
  });

  testWidgets('hides the scale control when no ingredient is scalable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);
    final recipe = Recipe(
      id: 'r2',
      name: '凉拌',
      category: '中餐',
      difficulty: 1,
      cookingMinutes: 5,
      description: '',
      ingredients: [
        RecipeIngredient(name: '盐', quantity: '', unit: '适量'),
        RecipeIngredient(name: '香油', quantity: '', unit: '少许'),
      ],
      steps: const [],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db, inventory: const []),
        ],
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: RecipeDetailScreen(recipe: recipe),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2×'), findsNothing);
  });
}
