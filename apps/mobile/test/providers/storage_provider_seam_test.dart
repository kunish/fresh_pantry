import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';

void main() {
  test('repos resolve from injected AppDatabase', () {
    final db = AppDatabase(NativeDatabase.memory());
    final c = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
    ]);
    addTearDown(c.dispose);
    addTearDown(db.close);
    expect(c.read(inventoryRepoProvider), isNotNull);
    expect(c.read(shoppingRepoProvider), isNotNull);
    expect(c.read(customRecipeRepoProvider), isNotNull);
    expect(c.read(syncOutboxRepoProvider), isNotNull);
  });
}
