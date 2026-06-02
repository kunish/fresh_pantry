import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/custom_recipe_form_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('paste banner appears at top of recipe form and expands to reveal inputs', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const MaterialApp(home: CustomRecipeFormScreen()),
    ));
    // Banner starts collapsed — expand it first.
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('recipe_url_input')), findsOneWidget);
    expect(find.byKey(const Key('recipe_url_parse')), findsOneWidget);
  });

  testWidgets('banner is not shown in edit mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Provide a non-null recipe to trigger edit mode.
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: CustomRecipeFormScreen(
          recipe: _stubRecipe(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('✨ 粘贴链接，AI 自动填表'), findsNothing);
    expect(find.byKey(const Key('recipe_url_input')), findsNothing);
  });

  testWidgets('parse button fills form inline and shows review banner', (tester) async {
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
    // Banner starts collapsed — expand it first.
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('recipe_url_input')), 'https://lanfanapp.com/recipe/15978');
    await tester.tap(find.byKey(const Key('recipe_url_parse')));
    await tester.pumpAndSettle();
    expect(find.text('番茄烤肠意面'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('个 ▾'), findsOneWidget);
    expect(find.text('煮面'), findsOneWidget);
    expect(find.byKey(const Key('ai_draft_review_banner')), findsOneWidget);
    expect(find.text('保存食谱'), findsOneWidget);
  });

  testWidgets('leaving form without saving clears ai draft on re-entry', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CustomRecipeFormScreen(
                        urlParserOverride: (url) async => _stubDraft(url),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('recipe_url_input')),
      'https://lanfanapp.com/recipe/15978',
    );
    await tester.tap(find.byKey(const Key('recipe_url_parse')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_draft_review_banner')), findsOneWidget);

    // FkTopBar 用自绘的圆形返回按钮(非 Material BackButton),点它的图标触发返回。
    // 解析会把草稿回填进表单 → 表单变脏 → 返回时弹出"丢弃更改"确认框。
    await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
    await tester.pumpAndSettle();
    expect(find.text('丢弃更改'), findsOneWidget);
    await tester.tap(find.text('丢弃'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_draft_review_banner')), findsNothing);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai_draft_review_banner')), findsNothing);
  });
}

Recipe _stubRecipe() => const Recipe(
      id: 'stub_1',
      name: '测试食谱',
      category: '家常',
      difficulty: 3,
      cookingMinutes: 30,
      description: '',
      ingredients: [],
      steps: ['步骤一'],
      tags: [],
    );

RecipeDraft _stubDraft(String url) => RecipeDraft(
      sourceUrl: url,
      name: DraftField.ai('番茄烤肠意面'),
      category: DraftField.ai('面'),
      cookingMinutes: DraftField.ai(20),
      difficulty: DraftField.ai(2),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: [
        RecipeIngredientDraft(
          name: DraftField.ai('番茄'),
          amount: DraftField.ai('2个'),
        ),
      ],
      steps: [DraftField.ai('煮面')],
    );
