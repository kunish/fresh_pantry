import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
import 'package:fresh_pantry/screens/recipe_draft_review_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('paste banner appears at top of recipe form', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: CustomRecipeFormScreen()),
    ));
    expect(find.byKey(const Key('recipe_url_input')), findsOneWidget);
    expect(find.byKey(const Key('recipe_url_parse')), findsOneWidget);
  });

  testWidgets('parse button with valid URL pushes RecipeDraftReviewScreen', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: CustomRecipeFormScreen(
          urlParserOverride: (url) async => _stubDraft(url),
        ),
      ),
    ));
    await tester.enterText(find.byKey(const Key('recipe_url_input')), 'https://lanfanapp.com/recipe/15978');
    await tester.tap(find.byKey(const Key('recipe_url_parse')));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeDraftReviewScreen), findsOneWidget);
  });
}

RecipeDraft _stubDraft(String url) => RecipeDraft(
      sourceUrl: url,
      name: DraftField.ai('Test'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(30),
      difficulty: DraftField.ai(2),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: const [],
      steps: const [],
    );
