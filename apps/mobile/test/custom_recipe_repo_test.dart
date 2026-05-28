import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';

void main() {
  group('CustomRecipeRepo.loadAll', () {
    test('returns [] when the key is missing', () {
      final repo = CustomRecipeRepo(InMemoryStorageAdapter());
      expect(repo.loadAll(), isEmpty);
    });

    test('salvages good recipes and skips only malformed ones', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        CustomRecipeRepo.storageKey,
        json.encode([
          {'id': 'r1', 'name': '番茄炒蛋'},
          {'id': 'r2', 'name': '坏', 'ingredients': 'not-a-list'}, // throws
          'not-an-object',
          {'id': 'r3', 'name': '青椒肉丝'},
        ]),
      );
      final repo = CustomRecipeRepo(adapter);

      final recipes = repo.loadAll();

      expect(recipes.map((r) => r.id), ['r1', 'r3']);
    });

    test('still filters out recipes with empty id or name', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        CustomRecipeRepo.storageKey,
        json.encode([
          {'id': '', 'name': '无效'},
          {'id': 'r1', 'name': ''},
          {'id': 'r2', 'name': '有效'},
        ]),
      );
      final repo = CustomRecipeRepo(adapter);

      expect(repo.loadAll().map((r) => r.id), ['r2']);
    });

    test(
      'a top-level non-list blob returns [] and leaves the blob intact',
      () {
        final adapter = InMemoryStorageAdapter();
        const intact = '{"not":"a list"}';
        adapter.write(CustomRecipeRepo.storageKey, intact);
        final repo = CustomRecipeRepo(adapter);

        expect(repo.loadAll(), isEmpty);
        expect(adapter.read(CustomRecipeRepo.storageKey), intact);
      },
    );
  });
}
