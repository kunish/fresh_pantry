import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

Ingredient _local(String name) => Ingredient(
      id: '',
      name: name,
      quantity: '1',
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1,
      state: FreshnessState.fresh,
    );

void main() {
  test('two empty-id local-only items both persist (no PK collision)', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = InventoryRepo(db);

    await repo.saveItems('', [_local('牛奶'), _local('鸡蛋')]);

    final loaded = await repo.loadAllFor('');
    expect(loaded.map((e) => e.name).toSet(), {'牛奶', '鸡蛋'});
  });

  test('v1->v2 upgrade preserves every row, including blank-id duplicates',
      () async {
    // Build a v1-shaped inventory_items table (sync id as PK is impossible to
    // duplicate, so v1 itself could only ever hold ONE blank-id row — the very
    // bug). Simulate two distinct rows the v1 PK would have allowed (distinct
    // ids) plus assert the upgrade machinery copies them across intact.
    final executor = NativeDatabase.memory();
    final raw = AppDatabase(executor); // opens at current schema (v2)
    // Emulate a legacy v1 table, then run the migrator from 1 -> 2.
    await raw.customStatement('DROP TABLE IF EXISTS inventory_items');
    await raw.customStatement(
      'CREATE TABLE inventory_items ('
      'id TEXT NOT NULL PRIMARY KEY, '
      'household_id TEXT NOT NULL DEFAULT \'\', '
      'name TEXT NOT NULL DEFAULT \'\', '
      'storage_area TEXT, '
      'expiry_date INTEGER, '
      'remote_version INTEGER NOT NULL DEFAULT 0, '
      'deleted_at INTEGER, '
      'payload_json TEXT NOT NULL)',
    );
    await raw.customStatement(
      "INSERT INTO inventory_items "
      "(id, household_id, name, remote_version, payload_json) VALUES "
      "('x', '', '牛奶', 0, '{\"id\":\"x\",\"name\":\"牛奶\",\"quantity\":\"1\","
      "\"unit\":\"盒\",\"imageUrl\":\"\",\"freshnessPercent\":1.0,"
      "\"state\":\"fresh\"}'), "
      "('y', '', '鸡蛋', 0, '{\"id\":\"y\",\"name\":\"鸡蛋\",\"quantity\":\"1\","
      "\"unit\":\"个\",\"imageUrl\":\"\",\"freshnessPercent\":1.0,"
      "\"state\":\"fresh\"}')",
    );

    await raw.migration.onUpgrade(Migrator(raw), 1, 2);

    final loaded = await InventoryRepo(raw).loadAllFor('');
    expect(loaded.map((e) => e.name).toSet(), {'牛奶', '鸡蛋'});
    await raw.close();
  });
}
