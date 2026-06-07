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

// Weekly meal-plan entries. `@DataClassName` renames the generated row class to
// `MealPlanRow` so it doesn't collide with the `MealPlanEntry` domain model
// (the same collision ShoppingItems hits, handled here at the source instead).
@DataClassName('MealPlanRow')
class MealPlanEntries extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))(); // recipeName
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
}

// Append-only food-departure log: one row per item leaving inventory, tagged
// consumed vs wasted. The waste-reduction stats are derived from these rows.
// `@DataClassName('FoodLogRow')` keeps the generated row class off the
// `FoodLogEntry` domain model name (same collision MealPlanEntries avoids).
@DataClassName('FoodLogRow')
class FoodLogEntries extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  // epoch ms — queryable so the stats provider can read a bounded recent window
  // instead of the whole (unbounded, append-only) history.
  IntColumn get loggedAt => integer().nullable()();
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
  InventoryItems, ShoppingItems, CustomRecipes, MealPlanEntries, FoodLogEntries,
  SyncOutbox, AddHistoryEntries,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 5;

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
          if (from < 4) {
            // New table only — no data transform, so the safest migration:
            // create it and its household index for existing installs.
            await m.createTable(mealPlanEntries);
            await _createMealPlanIndex();
          }
          if (from < 5) {
            // New append-only food log table + its scoped index.
            await m.createTable(foodLogEntries);
            await _createFoodLogIndex();
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
    await _createMealPlanIndex();
    await _createFoodLogIndex();
    await customStatement(
      'CREATE INDEX IF NOT EXISTS outbox_created_idx '
      'ON sync_outbox (created_at)',
    );
  }

  Future<void> _createMealPlanIndex() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS meal_plan_household_idx '
      'ON meal_plan_entries (household_id)',
    );
  }

  /// Composite (household, logged_at) so both the scoped load and the bounded
  /// recent-window stats query are index-served.
  Future<void> _createFoodLogIndex() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS food_log_household_logged_idx '
      'ON food_log_entries (household_id, logged_at)',
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
