import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/storage/shopping_repo.dart';

void main() {
  group('ShoppingRepo.loadAll', () {
    test('returns [] when the key is missing', () {
      final repo = ShoppingRepo(InMemoryStorageAdapter());
      expect(repo.loadAll(), isEmpty);
    });

    test('salvages good entries and skips only malformed ones', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        'shopping_items',
        json.encode([
          {'id': 'a', 'name': '牛奶', 'detail': '', 'category': '乳品蛋类'},
          {'id': 5, 'name': '坏'}, // bad: id wrong type
          {'id': 'c', 'name': '面包', 'detail': '', 'category': '主食'},
        ]),
      );
      final repo = ShoppingRepo(adapter);

      final items = repo.loadAll();

      expect(items.map((e) => e.name), ['牛奶', '面包']);
    });

    test('dedups by name on load (keeps the first of same-name rows)', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        'shopping_items',
        json.encode([
          {'id': 'a', 'name': '牛奶', 'detail': '低脂', 'category': '乳品蛋类'},
          {'id': 'b', 'name': '牛奶', 'detail': '全脂', 'category': '乳品蛋类'},
        ]),
      );
      final repo = ShoppingRepo(adapter);

      final items = repo.loadAll();

      // Shopping items are name-unique (add enforces it); load keeps the first.
      expect(items.map((e) => e.id), ['a']);
    });

    test('reassigns a unique id on duplicate ids instead of dropping', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        'shopping_items',
        json.encode([
          {'id': 'dup', 'name': '牛奶', 'detail': '', 'category': '乳品蛋类'},
          {'id': 'dup', 'name': '面包', 'detail': '', 'category': '主食'},
        ]),
      );
      final repo = ShoppingRepo(adapter);

      final items = repo.loadAll();

      expect(items, hasLength(2));
      expect(items.map((e) => e.id).toSet(), hasLength(2));
    });

    test('drops blank-name rows on load (name is the identity)', () {
      final adapter = InMemoryStorageAdapter();
      adapter.write(
        'shopping_items',
        json.encode([
          {'id': 'a', 'name': '', 'detail': '', 'category': '主食'},
        ]),
      );
      final repo = ShoppingRepo(adapter);

      expect(repo.loadAll(), isEmpty);
    });

    test(
      'a top-level non-list blob returns [] and leaves the blob intact',
      () {
        final adapter = InMemoryStorageAdapter();
        const intact = '{"not":"a list"}';
        adapter.write('shopping_items', intact);
        final repo = ShoppingRepo(adapter);

        expect(repo.loadAll(), isEmpty);
        expect(adapter.read('shopping_items'), intact);
      },
    );
  });
}
