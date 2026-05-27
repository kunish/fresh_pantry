import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/models/sync_metadata.dart';

void main() {
  group('FoodDetails.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = FoodDetails(
        displayName: '苹果',
        description: '新鲜苹果',
        imageUrl: 'https://example.com/apple.jpg',
        category: '果蔬生鲜',
        storage: IconType.fridge,
        shelfLifeDays: 14,
        source: 'test',
        fetchedAt: DateTime.utc(2026, 1, 15),
      );
      final json = original.toJson();
      final restored = FoodDetails.fromJson(json);

      expect(restored.displayName, original.displayName);
      expect(restored.description, original.description);
      expect(restored.imageUrl, original.imageUrl);
      expect(restored.category, original.category);
      expect(restored.storage, original.storage);
      expect(restored.shelfLifeDays, original.shelfLifeDays);
      expect(restored.source, original.source);
    });

    test('toJson always writes cacheVersion 4', () {
      final details = FoodDetails(
        displayName: '牛奶',
        description: '',
        imageUrl: null,
        category: '乳品蛋类',
        storage: IconType.fridge,
        shelfLifeDays: 7,
        source: 'test',
        fetchedAt: DateTime.utc(2026),
      );
      expect(details.toJson()['cacheVersion'], 4);
    });

    test('fromJson uses defaults for missing fields', () {
      final details = FoodDetails.fromJson({});
      expect(details.displayName, '');
      expect(details.description, '');
      expect(details.imageUrl, isNull);
      expect(details.shelfLifeDays, isNull);
      expect(
        details.fetchedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });

    test('fromJson handles null imageUrl', () {
      final json = {'displayName': '香蕉', 'imageUrl': null};
      expect(FoodDetails.fromJson(json).imageUrl, isNull);
    });

    test('fromJson falls back to epoch for invalid fetchedAt', () {
      final json = {'fetchedAt': 'not-a-date'};
      expect(
        FoodDetails.fromJson(json).fetchedAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    });
  });

  group('Ingredient.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = Ingredient(
        name: '番茄',
        quantity: '2',
        unit: '个',
        imageUrl: '',
        freshnessPercent: 0.8,
        state: FreshnessState.fresh,
        expiryLabel: '5天后过期',
        category: '果蔬生鲜',
        barcode: '1234567890',
        storage: IconType.fridge,
        expiryDate: DateTime.utc(2026, 6, 1),
        addedAt: DateTime.utc(2026, 5, 25),
        shelfLifeDays: 7,
      );
      final restored = Ingredient.fromJson(original.toJson());
      expect(restored, original);
    });

    test('fromJson uses defaults for missing fields', () {
      final ing = Ingredient.fromJson({});
      expect(ing.name, '');
      expect(ing.quantity, '1');
      expect(ing.unit, '份');
      expect(ing.state, FreshnessState.fresh);
      expect(ing.storage, IconType.fridge);
    });

    test(
      'fromJson tolerates unknown storage string — falls back to fridge',
      () {
        final ing = Ingredient.fromJson({'storage': 'unknown_storage_type'});
        expect(ing.storage, IconType.fridge);
      },
    );

    test('fromJson tolerates unknown state string — falls back to fresh', () {
      final ing = Ingredient.fromJson({'state': 'badValue'});
      expect(ing.state, FreshnessState.fresh);
    });

    test('fromJson maps freezer string to fridge (fallback behavior)', () {
      // IconType only has fridge/pantry; freezer maps to fridge by design
      final ing = Ingredient.fromJson({'storage': 'freezer'});
      expect(ing.storage, IconType.fridge);
    });
  });

  group('Recipe.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = Recipe(
        id: 'r1',
        name: '番茄炒蛋',
        category: '家常菜',
        difficulty: 2,
        cookingMinutes: 15,
        description: '简单家常菜',
        ingredients: [RecipeIngredient(name: '番茄', quantity: '2', unit: '个')],
        steps: ['切番茄', '炒鸡蛋'],
        tags: ['快手', '素菜'],
        imageUrl: null,
      );
      final restored = Recipe.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.difficulty, original.difficulty);
      expect(restored.cookingMinutes, original.cookingMinutes);
      expect(restored.ingredients.length, original.ingredients.length);
      expect(restored.steps, original.steps);
      expect(restored.tags, original.tags);
    });

    test('fromJson uses defaults for missing fields', () {
      final recipe = Recipe.fromJson({});
      expect(recipe.id, '');
      expect(recipe.name, '');
      expect(recipe.difficulty, 0);
      expect(recipe.cookingMinutes, 30);
      expect(recipe.ingredients, isEmpty);
      expect(recipe.steps, isEmpty);
      expect(recipe.tags, isEmpty);
      expect(recipe.imageUrl, isNull);
    });

    test('fromJson skips non-object elements in ingredients list', () {
      final recipe = Recipe.fromJson({
        'ingredients': [
          {'name': '番茄'},
          'not_an_object',
          42,
        ],
      });
      expect(recipe.ingredients.length, 1);
      expect(recipe.ingredients.first.name, '番茄');
    });
  });

  group('ShoppingItem.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = ShoppingItem(
        id: 'si_123',
        name: '牛奶',
        detail: '1 盒',
        imageUrl: 'https://example.com/milk.jpg',
        category: '乳品蛋类',
        isChecked: true,
      );
      final restored = ShoppingItem.fromJson(original.toJson());
      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.detail, original.detail);
      expect(restored.imageUrl, original.imageUrl);
      expect(restored.category, original.category);
      expect(restored.isChecked, original.isChecked);
    });

    test('fromJson uses defaults for missing fields', () {
      final item = ShoppingItem.fromJson({});
      expect(item.id, '');
      expect(item.name, '');
      expect(item.detail, '');
      expect(item.imageUrl, isNull);
      expect(item.isChecked, isFalse);
    });

    test('fromJson handles missing id gracefully', () {
      final item = ShoppingItem.fromJson({'name': '苹果'});
      expect(item.name, '苹果');
      expect(item.id, '');
    });
  });

  test('Ingredient preserves remote sync metadata', () {
    final item = Ingredient(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Milk',
      quantity: '1',
      unit: 'box',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      remoteVersion: 3,
      clientUpdatedAt: DateTime.utc(2026, 5, 27),
      deletedAt: DateTime.utc(2026, 5, 28),
    );

    final decoded = Ingredient.fromJson(item.toJson());

    expect(decoded.id, item.id);
    expect(decoded.remoteVersion, 3);
    expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
    expect(decoded.deletedAt, DateTime.utc(2026, 5, 28));
  });

  test('ShoppingItem preserves remote sync metadata', () {
    final item = ShoppingItem(
      id: '22222222-2222-2222-2222-222222222222',
      name: 'Rice',
      detail: '5kg',
      category: '主食',
      remoteVersion: 4,
      clientUpdatedAt: DateTime.utc(2026, 5, 27),
    );

    final decoded = ShoppingItem.fromJson(item.toJson());

    expect(decoded.id, item.id);
    expect(decoded.remoteVersion, 4);
    expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
  });

  test('Recipe preserves remote sync metadata', () {
    final recipe = Recipe(
      id: '33333333-3333-3333-3333-333333333333',
      name: 'Soup',
      category: '晚餐',
      difficulty: 2,
      cookingMinutes: 30,
      description: 'Simple soup',
      ingredients: const [],
      steps: const ['Cook'],
      remoteVersion: 2,
      clientUpdatedAt: DateTime.utc(2026, 5, 27),
    );

    final decoded = Recipe.fromJson(recipe.toJson());

    expect(decoded.id, recipe.id);
    expect(decoded.remoteVersion, 2);
    expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
  });

  test('Pantry models can clear nullable sync timestamps', () {
    final updatedAt = DateTime.utc(2026, 5, 27);
    final deletedAt = DateTime.utc(2026, 5, 28);

    final ingredient = Ingredient(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Milk',
      quantity: '1',
      unit: 'box',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );
    final clearedIngredient = ingredient.copyWith(
      clearClientUpdatedAt: true,
      clearDeletedAt: true,
    );

    expect(clearedIngredient.clientUpdatedAt, isNull);
    expect(clearedIngredient.deletedAt, isNull);

    final shoppingItem = ShoppingItem(
      id: '22222222-2222-2222-2222-222222222222',
      name: 'Rice',
      detail: '5kg',
      category: '主食',
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );
    final clearedShoppingItem = shoppingItem.copyWith(
      clearClientUpdatedAt: true,
      clearDeletedAt: true,
    );

    expect(clearedShoppingItem.clientUpdatedAt, isNull);
    expect(clearedShoppingItem.deletedAt, isNull);

    final recipe = Recipe(
      id: '33333333-3333-3333-3333-333333333333',
      name: 'Soup',
      category: '晚餐',
      difficulty: 2,
      cookingMinutes: 30,
      description: 'Simple soup',
      ingredients: const [],
      steps: const ['Cook'],
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );
    final clearedRecipe = recipe.copyWith(
      clearClientUpdatedAt: true,
      clearDeletedAt: true,
    );

    expect(clearedRecipe.clientUpdatedAt, isNull);
    expect(clearedRecipe.deletedAt, isNull);
  });

  test('Pantry models expose sync metadata value objects', () {
    final updatedAt = DateTime.utc(2026, 5, 27);
    final deletedAt = DateTime.utc(2026, 5, 28);

    final ingredient = Ingredient(
      id: '11111111-1111-1111-1111-111111111111',
      name: 'Milk',
      quantity: '1',
      unit: 'box',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
      remoteVersion: 3,
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );

    expect(
      ingredient.syncMetadata,
      SyncMetadata(
        remoteVersion: 3,
        clientUpdatedAt: updatedAt,
        deletedAt: deletedAt,
      ),
    );

    final shoppingItem = ShoppingItem(
      id: '22222222-2222-2222-2222-222222222222',
      name: 'Rice',
      detail: '5kg',
      category: '主食',
      remoteVersion: 4,
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );

    expect(
      shoppingItem.syncMetadata,
      SyncMetadata(
        remoteVersion: 4,
        clientUpdatedAt: updatedAt,
        deletedAt: deletedAt,
      ),
    );

    final recipe = Recipe(
      id: '33333333-3333-3333-3333-333333333333',
      name: 'Soup',
      category: '晚餐',
      difficulty: 2,
      cookingMinutes: 30,
      description: 'Simple soup',
      ingredients: const [],
      steps: const ['Cook'],
      remoteVersion: 2,
      clientUpdatedAt: updatedAt,
      deletedAt: deletedAt,
    );

    expect(
      recipe.syncMetadata,
      SyncMetadata(
        remoteVersion: 2,
        clientUpdatedAt: updatedAt,
        deletedAt: deletedAt,
      ),
    );
  });
}
