import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class InventoryItems extends Table {
  // Surrogate autoincrement PK. The sync `id` cannot be the primary key:
  // local-only rows legitimately share an empty id (a project invariant —
  // Ingredient.id is blank until a household is joined), so an id PK collapses
  // every local row onto '' and silently drops all but the last.
  IntColumn get rowPk => integer().autoIncrement()();
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get storageArea => text().nullable()();
  IntColumn get expiryDate => integer().nullable()(); // epoch ms
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()(); // epoch ms
  TextColumn get payloadJson => text()();
}

class ShoppingItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isChecked => boolean().withDefault(const Constant(false))();
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class CustomRecipes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

class SyncOutbox extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  IntColumn get baseVersion => integer().nullable()();
  TextColumn get clientId => text()();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get payloadJson => text()(); // SyncOperation.toJson()
  @override
  Set<Column> get primaryKey => {id};
}

class AddHistoryEntries extends Table {
  TextColumn get name => text()();      // 频次记忆 key
  TextColumn get payloadJson => text()(); // {count,category,storage,unit}
  @override
  Set<Column> get primaryKey => {name};
}

@DriftDatabase(tables: [
  InventoryItems, ShoppingItems, CustomRecipes, SyncOutbox, AddHistoryEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 used the sync `id` as the inventory PK, which collided for
            // local-only rows (blank id). Rebuild the table with a surrogate
            // autoincrement PK, copying every existing row over (each gets a
            // fresh rowPk, so previously-colliding blank-id rows all survive).
            await customStatement(
              'ALTER TABLE inventory_items RENAME TO inventory_items_v1',
            );
            await m.createTable(inventoryItems);
            await customStatement(
              'INSERT INTO inventory_items '
              '(id, household_id, name, storage_area, expiry_date, '
              'remote_version, deleted_at, payload_json) '
              'SELECT id, household_id, name, storage_area, expiry_date, '
              'remote_version, deleted_at, payload_json '
              'FROM inventory_items_v1',
            );
            await customStatement('DROP TABLE inventory_items_v1');
            await customStatement(
              'CREATE INDEX IF NOT EXISTS inventory_household_idx '
              'ON inventory_items (household_id)',
            );
          }
          if (from < 3) {
            await _dedupeInventory();
            await _createInventoryIdUniqueIndex();
          }
        },
      );

  /// Collapses the duplicate inventory rows the pre-v3 sync path accumulated,
  /// then a partial unique index (added separately) keeps them from returning.
  ///
  /// Two distinct duplication shapes are cleaned:
  ///   1. Orphan twins — a local-only ('' scope) row left behind after its
  ///      logical item was adopted into a household under the same sync id.
  ///   2. Re-minted clones — the same logical item (identical name + addedAt)
  ///      re-uploaded under fresh ids on later sync passes.
  /// The lexicographically smallest id wins, matching the server-side cleanup so
  /// both stores converge on the same surviving row.
  Future<void> _dedupeInventory() async {
    // 1a. Drop '' orphans whose id also exists in a real household.
    await customStatement(
      "DELETE FROM inventory_items "
      "WHERE household_id = '' AND id != '' AND id IN "
      "(SELECT id FROM inventory_items WHERE household_id != '')",
    );
    // 1a'. Drop '' orphans that duplicate a household item by name + addedAt —
    //      catches twins whose household copy was re-minted under a different id
    //      (or removed by a server tombstone). addedAt must be present so a
    //      genuine local-only row, which has no household twin, is never touched.
    await customStatement(
      "DELETE FROM inventory_items WHERE household_id = '' "
      "AND json_extract(payload_json, '\$.addedAt') IS NOT NULL "
      "AND EXISTS (SELECT 1 FROM inventory_items h "
      "WHERE h.household_id != '' AND h.name = inventory_items.name "
      "AND json_extract(h.payload_json, '\$.addedAt') = "
      "json_extract(inventory_items.payload_json, '\$.addedAt'))",
    );
    // 1b. Collapse any remaining exact-id duplicates, keeping the earliest row.
    await customStatement(
      "DELETE FROM inventory_items WHERE id != '' AND row_pk NOT IN "
      "(SELECT MIN(row_pk) FROM inventory_items WHERE id != '' GROUP BY id)",
    );
    // 2. Collapse re-minted clones: same household + name + addedAt, keep the
    //    smallest id. addedAt must be present so genuinely distinct items
    //    (different add times, or no timestamp) are never merged.
    await customStatement(
      "DELETE FROM inventory_items WHERE row_pk IN ("
      "SELECT a.row_pk FROM inventory_items a "
      "JOIN inventory_items b "
      "ON a.household_id = b.household_id AND a.name = b.name "
      "AND json_extract(a.payload_json, '\$.addedAt') = "
      "json_extract(b.payload_json, '\$.addedAt') "
      "WHERE a.household_id != '' "
      "AND json_extract(a.payload_json, '\$.addedAt') IS NOT NULL "
      "AND b.id < a.id)",
    );
  }

  Future<void> _createInventoryIdUniqueIndex() async {
    // Partial: local-only rows legitimately share a blank id, so only non-empty
    // sync ids are constrained to be unique (one row per logical item).
    await customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS inventory_id_unique "
      "ON inventory_items (id) WHERE id != ''",
    );
  }

  Future<void> _createIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS inventory_household_idx '
      'ON inventory_items (household_id)',
    );
    await _createInventoryIdUniqueIndex();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS shopping_household_idx '
      'ON shopping_items (household_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS recipes_household_idx '
      'ON custom_recipes (household_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS outbox_created_idx '
      'ON sync_outbox (created_at)',
    );
  }

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'fresh_pantry',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
