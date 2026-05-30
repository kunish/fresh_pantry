import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class InventoryItems extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text().withDefault(const Constant(''))();
  TextColumn get name => text().withDefault(const Constant(''))();
  TextColumn get storageArea => text().nullable()();
  IntColumn get expiryDate => integer().nullable()(); // epoch ms
  IntColumn get remoteVersion => integer().withDefault(const Constant(0))();
  IntColumn get deletedAt => integer().nullable()(); // epoch ms
  TextColumn get payloadJson => text()();
  @override
  Set<Column> get primaryKey => {id};
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX IF NOT EXISTS inventory_household_idx '
            'ON inventory_items (household_id)',
          );
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
        },
      );

  static QueryExecutor _open() {
    return driftDatabase(
      name: 'fresh_pantry',
      native: const DriftNativeOptions(
        databaseDirectory: getApplicationSupportDirectory,
      ),
    );
  }
}
