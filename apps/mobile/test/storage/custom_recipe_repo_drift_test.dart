import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

Recipe _recipe(String id, String name) => Recipe(
      id: id,
      name: name,
      category: '家常菜',
      difficulty: 1,
      cookingMinutes: 15,
      description: '',
      ingredients: const [],
      steps: const [],
    );

void main() {
  test('saveRecipes then loadAllFor round-trips, skips blank id/name', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final repo = CustomRecipeRepo(db);

    await repo.saveRecipes('hh-1', [
      _recipe('r1', 'Soup'),
      _recipe('', 'Blank'),
    ]);

    final loaded = await repo.loadAllFor('hh-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'r1');

    await db.close();
  });
}
