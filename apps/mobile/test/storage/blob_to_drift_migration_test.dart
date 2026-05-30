import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/storage/blob_to_drift_migration.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({
        legacyInventoryKey: jsonEncode([
          {
            'id': 'a',
            'name': '牛奶',
            'quantity': '1',
            'unit': '盒',
            'imageUrl': '',
            'freshnessPercent': 1.0,
            'state': 'fresh',
          }
        ]),
        legacyOutboxKey: jsonEncode([
          {
            'id': 'op1',
            'householdId': 'h1',
            'entityType': 'inventoryItem',
            'entityId': 'a',
            'operation': 'create',
            'patch': {},
            'clientId': 'c',
            'createdAt': '2026-01-01T00:00:00.000Z',
          }
        ]),
      }));

  test('imports blobs once; idempotent on second run', () async {
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    final repo = InventoryRepo(db);
    expect((await repo.loadAllFor('')).map((e) => e.name), ['牛奶']);
    final outbox = await db.select(db.syncOutbox).get();
    expect(outbox.length, 1);

    // 落库作用域为 local-only（householdId == ''，与冷启动种子一致）。
    final invRows = await db.select(db.inventoryItems).get();
    expect(invRows.single.householdId, '');

    // legacy blob 不被删除（保留一个版本作为回滚路径）。
    expect(prefs.getString(legacyInventoryKey), isNotNull);
    expect(prefs.getString(legacyOutboxKey), isNotNull);

    // 二次运行不重复导入
    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    expect((await repo.loadAllFor('')).length, 1);
    expect((await db.select(db.syncOutbox).get()).length, 1);
  });

  test('skips a single malformed entry, keeps the rest', () async {
    SharedPreferences.setMockInitialValues({
      legacyInventoryKey: jsonEncode([
        {
          'id': 'a',
          'name': '牛奶',
          'quantity': '1',
          'unit': '盒',
          'imageUrl': '',
          'freshnessPercent': 1.0,
          'state': 'fresh',
        },
        {'totally': 'broken'},
      ]),
      legacyOutboxKey: jsonEncode([
        {
          'id': 'op1',
          'householdId': 'h1',
          'entityType': 'inventoryItem',
          'entityId': 'a',
          'operation': 'create',
          'patch': {},
          'clientId': 'c',
          'createdAt': '2026-01-01T00:00:00.000Z',
        },
        {'id': 'bad'},
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    expect((await InventoryRepo(db).loadAllFor('')).length, 1);
    expect((await db.select(db.syncOutbox).get()).length, 1);
  });

  test('flag already set short-circuits', () async {
    SharedPreferences.setMockInitialValues({
      migratedFlagKey: true,
      legacyInventoryKey: jsonEncode([
        {
          'id': 'a',
          'name': 'x',
          'quantity': '1',
          'unit': '个',
          'imageUrl': '',
          'freshnessPercent': 1.0,
          'state': 'fresh',
        }
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await migratePrefsBlobsToDrift(prefs: prefs, db: db);
    expect(await InventoryRepo(db).loadAllFor(''), isEmpty);
  });
}
