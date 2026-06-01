import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

/// Builds a payload_json string for a v2-shaped inventory row.
String _payload(String id, String name, String addedAt) =>
    '{"id":"$id","name":"$name","quantity":"1","unit":"个","imageUrl":"",'
    '"freshnessPercent":1.0,"state":"fresh","addedAt":"$addedAt"}';

/// Recreates the v2 inventory_items table shape (surrogate row_pk PK, no unique
/// constraint on the sync id) so we can drive the v2 -> v3 dedup upgrade.
Future<void> _seedV2Table(AppDatabase db) async {
  await db.customStatement('DROP TABLE IF EXISTS inventory_items');
  await db.customStatement(
    'CREATE TABLE inventory_items ('
    'row_pk INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'id TEXT NOT NULL, '
    'household_id TEXT NOT NULL DEFAULT \'\', '
    'name TEXT NOT NULL DEFAULT \'\', '
    'storage_area TEXT, '
    'expiry_date INTEGER, '
    'remote_version INTEGER NOT NULL DEFAULT 0, '
    'deleted_at INTEGER, '
    'payload_json TEXT NOT NULL)',
  );
}

Future<void> _insertRow(
  AppDatabase db, {
  required String id,
  required String household,
  required String name,
  required String addedAt,
}) {
  return db.customStatement(
    'INSERT INTO inventory_items (id, household_id, name, payload_json) '
    'VALUES (?, ?, ?, ?)',
    [id, household, name, _payload(id, name, addedAt)],
  );
}

void main() {
  const addedSoy = '2026-05-30T13:24:41.539887Z';
  const addedSalt = '2026-05-29T00:00:00.000000Z';
  const addedLocal = '2026-05-31T00:00:00.000000Z';

  test('v2->v3 collapses orphan twins and same-(name,addedAt) clones', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedV2Table(db);

    // 生抽: one '' orphan sharing id with a household twin, plus two extra
    // clones that carry fresh ids but the identical addedAt (the real bug).
    await _insertRow(db, id: 'id-a', household: '', name: '生抽', addedAt: addedSoy);
    await _insertRow(db, id: 'id-a', household: 'h1', name: '生抽', addedAt: addedSoy);
    await _insertRow(db, id: 'id-b', household: 'h1', name: '生抽', addedAt: addedSoy);
    await _insertRow(db, id: 'id-c', household: 'h1', name: '生抽', addedAt: addedSoy);
    // 盐: a clean single household row.
    await _insertRow(db, id: 'id-x', household: 'h1', name: '盐', addedAt: addedSalt);
    // 陈醋: an orphan whose household twin survives under a DIFFERENT id (its
    // same-id twin was already removed, e.g. by a server-side tombstone). It
    // must still collapse, matched by name + addedAt rather than id.
    await _insertRow(db, id: 'id-d', household: '', name: '陈醋', addedAt: addedSoy);
    await _insertRow(db, id: 'id-e', household: 'h1', name: '陈醋', addedAt: addedSoy);
    // A genuine local-only row with NO household twin must survive untouched.
    await _insertRow(db, id: 'id-z', household: '', name: '本地菜', addedAt: addedLocal);

    await db.migration.onUpgrade(Migrator(db), 2, 3);

    final repo = InventoryRepo(db);
    final household = await repo.loadAllFor('h1');
    expect(
      household.map((e) => e.name),
      unorderedEquals(['生抽', '盐', '陈醋']),
      reason: '生抽 must collapse to a single household row',
    );
    final soy = household.where((e) => e.name == '生抽').toList();
    expect(soy.single.id, 'id-a',
        reason: 'canonical survivor is the lexicographically smallest id');

    expect((await repo.loadAllFor('')).map((e) => e.name), ['本地菜'],
        reason: 'both orphans dropped; genuine local-only row preserved');
  });

  test('v3 partial unique index rejects a duplicate non-empty id', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await _seedV2Table(db);
    await _insertRow(db, id: 'dup', household: 'h1', name: '醋', addedAt: addedSalt);

    await db.migration.onUpgrade(Migrator(db), 2, 3);

    await expectLater(
      _insertRow(db, id: 'dup', household: 'h1', name: '醋', addedAt: addedSalt),
      throwsA(anything),
      reason: 'a non-empty id must be unique once v3 is applied',
    );
  });
}
