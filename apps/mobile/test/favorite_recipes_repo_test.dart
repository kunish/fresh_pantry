import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/favorite_recipes_repo.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';

void main() {
  group('FavoriteRecipesRepo', () {
    test('load returns {} when the key is missing', () {
      final repo = FavoriteRecipesRepo(InMemoryStorageAdapter());
      expect(repo.load(), isEmpty);
    });

    test('load returns {} for an empty stored string', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(FavoriteRecipesRepo.storageKey, '');
      expect(FavoriteRecipesRepo(adapter).load(), isEmpty);
    });

    test('save then load round-trips the id set', () {
      final adapter = InMemoryStorageAdapter();
      final repo = FavoriteRecipesRepo(adapter);

      repo.save({'r1', 'r2', 'r3'});

      expect(repo.load(), {'r1', 'r2', 'r3'});
    });

    test('save survives a fresh repo over the same adapter', () {
      final adapter = InMemoryStorageAdapter();
      FavoriteRecipesRepo(adapter).save({'r1', 'r2'});

      expect(FavoriteRecipesRepo(adapter).load(), {'r1', 'r2'});
    });

    test('malformed (non-JSON) blob yields {} instead of throwing', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(FavoriteRecipesRepo.storageKey, 'not-json{[');
      expect(FavoriteRecipesRepo(adapter).load(), isEmpty);
    });

    test('non-list JSON blob yields {}', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(FavoriteRecipesRepo.storageKey, '{"r1":true}');
      expect(FavoriteRecipesRepo(adapter).load(), isEmpty);
    });

    test('skips non-string and empty entries, keeps valid ids', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        FavoriteRecipesRepo.storageKey,
        json.encode(['r1', 5, '', null, 'r2']),
      );
      expect(FavoriteRecipesRepo(adapter).load(), {'r1', 'r2'});
    });
  });
}
