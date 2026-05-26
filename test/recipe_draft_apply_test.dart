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
  });
}
