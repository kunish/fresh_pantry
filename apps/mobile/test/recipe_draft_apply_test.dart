import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/utils/recipe_draft_apply.dart';

void main() {
  group('recipeDraftToApplyResult', () {
    test('maps draft fields and ingredient amounts into form rows', () {
      final draft = RecipeDraft(
        sourceUrl: 'https://x',
        name: DraftField.ai('番茄烤肠意面'),
        category: DraftField.ai('面'),
        cookingMinutes: DraftField.ai(20),
        difficulty: DraftField.ai(2),
        description: DraftField.ai('简介'),
        imageUrl: const DraftField(value: null, source: DraftSource.ai),
        ingredients: [
          RecipeIngredientDraft(
            name: DraftField.ai('番茄'),
            amount: DraftField.ai('2个'),
          ),
        ],
        steps: [DraftField.ai('煮面')],
      );

      final applied = recipeDraftToApplyResult(
        draft,
        isSupportedImageSource: (_) => false,
      );

      expect(applied.name, '番茄烤肠意面');
      expect(applied.category, '面');
      expect(applied.cookingMinutes, '20');
      expect(applied.difficulty, '2');
      expect(applied.description, '简介');
      expect(applied.coverImageSource, isNull);
      expect(applied.ingredients.single.name, '番茄');
      expect(applied.ingredients.single.quantity, '2');
      expect(applied.ingredients.single.unit, '个');
      expect(applied.steps, ['煮面']);
    });

    test('keeps descriptive amounts like 少许 in quantity field', () {
      final draft = RecipeDraft(
        sourceUrl: 'https://x',
        name: DraftField.ai(''),
        category: DraftField.ai(''),
        cookingMinutes: DraftField.ai(0),
        difficulty: DraftField.ai(1),
        description: DraftField.ai(''),
        imageUrl: const DraftField(value: null, source: DraftSource.ai),
        ingredients: [
          RecipeIngredientDraft(
            name: DraftField.ai('盐'),
            amount: DraftField.ai('少许'),
          ),
        ],
        steps: const [],
      );

      final applied = recipeDraftToApplyResult(
        draft,
        isSupportedImageSource: (_) => false,
      );

      expect(applied.ingredients.single.quantity, '少许');
      expect(applied.ingredients.single.unit, isEmpty);
    });

    test('keeps fractional amount intact without splitting on slash', () {
      RecipeIngredientDraft buildIngredient(String amount) => RecipeIngredientDraft(
            name: DraftField.ai('面粉'),
            amount: DraftField.ai(amount),
          );

      RecipeDraft buildDraft(String amount) => RecipeDraft(
            sourceUrl: 'https://x',
            name: DraftField.ai(''),
            category: DraftField.ai(''),
            cookingMinutes: DraftField.ai(30),
            difficulty: DraftField.ai(1),
            description: DraftField.ai(''),
            imageUrl: const DraftField(value: null, source: DraftSource.ai),
            ingredients: [buildIngredient(amount)],
            steps: const [],
          );

      // '1/2个' — '个' is a known unit, so quantity='1/2', unit='个'
      final half = recipeDraftToApplyResult(
        buildDraft('1/2个'),
        isSupportedImageSource: (_) => false,
      );
      expect(half.ingredients.single.quantity, '1/2');
      expect(half.ingredients.single.unit, '个');

      // '2-3根' — '根' is a known unit, so quantity='2-3', unit='根'
      final range = recipeDraftToApplyResult(
        buildDraft('2-3根'),
        isSupportedImageSource: (_) => false,
      );
      expect(range.ingredients.single.quantity, '2-3');
      expect(range.ingredients.single.unit, '根');

      // '1/2碗' — '碗' is NOT a known unit, so whole thing stays in quantity
      final halfBowl = recipeDraftToApplyResult(
        buildDraft('1/2碗'),
        isSupportedImageSource: (_) => false,
      );
      expect(halfBowl.ingredients.single.quantity, '1/2碗');
      expect(halfBowl.ingredients.single.unit, isEmpty);
    });
  });
}
