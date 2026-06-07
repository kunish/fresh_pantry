import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/widgets/recipe_card.dart';

Recipe _recipe() => Recipe(
  id: 'r1',
  name: '番茄炒蛋',
  category: '家常',
  difficulty: 1,
  cookingMinutes: 15,
  description: '',
  ingredients: [RecipeIngredient(name: '番茄', quantity: '2', unit: '个')],
  steps: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required Widget card,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(useMaterial3: false),
      home: Scaffold(body: card),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tapping the heart toggles favorite without firing the card tap', (
    tester,
  ) async {
    var opened = 0;
    var toggled = 0;
    await _pump(
      tester,
      card: RecipeCard(
        recipe: _recipe(),
        matchedCount: 0,
        onTap: () => opened++,
        isFavorite: false,
        onToggleFavorite: () => toggled++,
      ),
    );

    await tester.tap(find.byKey(const Key('recipe_card_favorite_r1')));
    await tester.pumpAndSettle();

    expect(toggled, 1);
    expect(opened, 0);
  });

  testWidgets('shows a filled heart when the recipe is favorited', (
    tester,
  ) async {
    await _pump(
      tester,
      card: RecipeCard(
        recipe: _recipe(),
        matchedCount: 0,
        isFavorite: true,
        onToggleFavorite: () {},
      ),
    );
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
  });

  testWidgets('renders no heart when onToggleFavorite is omitted', (
    tester,
  ) async {
    await _pump(tester, card: RecipeCard(recipe: _recipe(), matchedCount: 0));
    expect(find.byKey(const Key('recipe_card_favorite_r1')), findsNothing);
  });
}
