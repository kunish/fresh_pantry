import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('inventory round-trips by household scope', () async {
    await db.into(db.inventoryItems).insert(
          InventoryItemsCompanion.insert(
            id: 'a',
            householdId: const Value('h1'),
            name: const Value('牛奶'),
            payloadJson: '{"id":"a","name":"牛奶"}',
            remoteVersion: const Value(0),
          ),
        );
    final rows = await (db.select(db.inventoryItems)
          ..where((t) => t.householdId.equals('h1')))
        .get();
    expect(rows.single.name, '牛奶');
    expect(rows.single.payloadJson, contains('牛奶'));
  });

  test('outbox orders by createdAt ascending', () async {
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
        id: 'op2', householdId: 'h1', entityType: 'inventoryItem',
        entityId: 'a', operation: 'create', clientId: 'c',
        createdAt: DateTime.utc(2026, 1, 2), payloadJson: '{}'));
    await db.into(db.syncOutbox).insert(SyncOutboxCompanion.insert(
        id: 'op1', householdId: 'h1', entityType: 'inventoryItem',
        entityId: 'a', operation: 'update', clientId: 'c',
        createdAt: DateTime.utc(2026, 1, 1), payloadJson: '{}'));
    final ops = await (db.select(db.syncOutbox)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
    expect(ops.map((o) => o.id), ['op1', 'op2']);
  });
}
