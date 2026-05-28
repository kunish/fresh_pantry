import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/in_memory_storage_adapter.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

void main() {
  group('InventoryRepo.loadAll', () {
    test('returns [] when the key is missing', () {
      final repo = InventoryRepo(InMemoryStorageAdapter());
      expect(repo.loadAll(), isEmpty);
    });

    test('salvages good entries and skips only malformed ones', () {
      final adapter = InMemoryStorageAdapter();
      // Mix of a valid item, a type-mismatched item (name is an int → throws
      // during fromJson), and a non-object entry.
      adapter.write(
        'inventory_items',
        json.encode([
          {'id': 'a', 'name': '苹果'},
          {'id': 'b', 'name': 123}, // bad: name wrong type
          'not-an-object',
          {'id': 'c', 'name': '香蕉'},
        ]),
      );
      final repo = InventoryRepo(adapter);

      final items = repo.loadAll();

      expect(items.map((e) => e.name), ['苹果', '香蕉']);
    });

    test(
      'does NOT collapse to [] when only one entry is malformed',
      () {
        final adapter = InMemoryStorageAdapter();
        adapter.write(
          'inventory_items',
          json.encode([
            {'id': 'a', 'name': '苹果'},
            {'id': 'b', 'name': false}, // bad
          ]),
        );
        final repo = InventoryRepo(adapter);

        expect(repo.loadAll().single.name, '苹果');
      },
    );

    test(
      'a top-level non-list blob returns [] and leaves the blob intact',
      () {
        final adapter = InMemoryStorageAdapter();
        const intact = '{"not":"a list"}';
        adapter.write('inventory_items', intact);
        final repo = InventoryRepo(adapter);

        expect(repo.loadAll(), isEmpty);
        // The repo did not rewrite storage on a failed read.
        expect(adapter.read('inventory_items'), intact);
      },
    );

    test('a malformed (unparseable) blob returns [] without rewriting it', () {
      final adapter = InMemoryStorageAdapter();
      const intact = '[{"name":"苹果"'; // truncated
      adapter.write('inventory_items', intact);
      final repo = InventoryRepo(adapter);

      expect(repo.loadAll(), isEmpty);
      expect(adapter.read('inventory_items'), intact);
    });
  });
}
