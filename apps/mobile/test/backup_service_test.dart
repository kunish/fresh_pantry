import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/services/backup_service.dart';

BackupData _sampleData() => BackupData(
  inventory: [
    Ingredient(
      id: 'ing_1',
      name: '苹果',
      quantity: '3',
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
    ),
  ],
  addHistory: {
    '葱': {'count': 3, 'category': '蔬菜', 'storage': 'fridge', 'unit': '把'},
  },
  shopping: [
    ShoppingItem.fromJson({'id': 'si_1', 'name': '酱油', 'category': '调料'}),
  ],
  customRecipes: [
    Recipe.fromJson({
      'id': 'r_1',
      'name': '番茄炒蛋',
      'ingredients': [],
      'steps': ['打蛋'],
    }),
  ],
  mealPlan: [
    MealPlanEntry(
      id: 'mp_1',
      date: DateTime(2026, 6, 8),
      recipeId: 'r_1',
      recipeName: '番茄炒蛋',
      servings: 2,
    ),
  ],
  aiSettings: AiSettings.empty,
);

void main() {
  group('BackupService.encode', () {
    test('produces a version 2 envelope with exportedAt + structured data', () {
      final root =
          jsonDecode(BackupService.encode(_sampleData()))
              as Map<String, dynamic>;

      expect(root['version'], 2);
      expect(DateTime.tryParse(root['exportedAt'] as String), isNotNull);
      final data = root['data'] as Map<String, dynamic>;
      expect(data['inventory'], isA<List<dynamic>>());
      expect(data['shopping'], isA<List<dynamic>>());
      expect(data['customRecipes'], isA<List<dynamic>>());
      expect(data['mealPlan'], isA<List<dynamic>>());
      expect(data['addHistory'], isA<Map<String, dynamic>>());
    });

    test('is pretty-printed (indent 2)', () {
      expect(BackupService.encode(_sampleData()), contains('\n  '));
    });

    test('omits aiSettings when null', () {
      final root =
          jsonDecode(
                BackupService.encode(
                  BackupData(
                    inventory: const [],
                    addHistory: const {},
                    shopping: const [],
                    customRecipes: const [],
                    mealPlan: const [],
                    aiSettings: null,
                  ),
                ),
              )
              as Map<String, dynamic>;
      expect(
        (root['data'] as Map<String, dynamic>).containsKey('aiSettings'),
        isFalse,
      );
    });
  });

  group('BackupService encode -> decode round-trip', () {
    test('preserves every entity by content', () {
      final original = _sampleData();
      final restored = BackupService.decode(BackupService.encode(original));

      expect(
        restored.inventory.map((i) => i.toJson()).toList(),
        original.inventory.map((i) => i.toJson()).toList(),
      );
      expect(restored.addHistory, original.addHistory);
      expect(
        restored.shopping.map((s) => s.toJson()).toList(),
        original.shopping.map((s) => s.toJson()).toList(),
      );
      expect(
        restored.customRecipes.map((r) => r.toJson()).toList(),
        original.customRecipes.map((r) => r.toJson()).toList(),
      );
      expect(
        restored.mealPlan.map((e) => e.toJson()).toList(),
        original.mealPlan.map((e) => e.toJson()).toList(),
      );
      expect(restored.aiSettings?.toJson(), original.aiSettings?.toJson());
    });
  });

  group('BackupService.decode validation', () {
    test('throws FormatException on malformed JSON', () {
      expect(() => BackupService.decode('{not valid'), throwsFormatException);
    });

    test('throws FormatException when the root is not an object', () {
      expect(() => BackupService.decode('[1,2,3]'), throwsFormatException);
    });

    test('throws BackupVersionException on unsupported version', () {
      expect(
        () => BackupService.decode('{"version": 99, "data": {}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('throws BackupVersionException when version is missing', () {
      expect(
        () => BackupService.decode('{"data": {}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('throws BackupVersionException for a float version', () {
      expect(
        () => BackupService.decode('{"version": 2.0, "data": {}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('throws FormatException when a list payload is not a list', () {
      expect(
        () => BackupService.decode(
          '{"version": 2, "data": {"inventory": {"not": "a list"}}}',
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when addHistory is not a map', () {
      expect(
        () => BackupService.decode(
          '{"version": 2, "data": {"addHistory": [1,2,3]}}',
        ),
        throwsFormatException,
      );
    });

    test('missing payload keys decode to empty/null (never throws)', () {
      final data = BackupService.decode('{"version": 2, "data": {}}');
      expect(data.inventory, isEmpty);
      expect(data.shopping, isEmpty);
      expect(data.customRecipes, isEmpty);
      expect(data.mealPlan, isEmpty);
      expect(data.addHistory, isEmpty);
      expect(data.aiSettings, isNull);
    });
  });
}
