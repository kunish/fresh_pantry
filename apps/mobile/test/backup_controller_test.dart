import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/models/shopping_item.dart';
import 'package:fresh_pantry/providers/ai_settings_provider.dart';
import 'package:fresh_pantry/providers/backup_controller.dart';
import 'package:fresh_pantry/providers/custom_recipe_provider.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/shopping_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/backup_service.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

const _aiSettings = AiSettings(
  baseUrl: 'https://api.example.com',
  apiKey: 'k1',
  model: 'gpt-x',
);

BackupData _fullBackup() => BackupData(
  inventory: const [
    Ingredient(
      id: 'ing_1',
      name: '番茄',
      quantity: '2',
      unit: '个',
      imageUrl: '',
      freshnessPercent: 1.0,
      state: FreshnessState.fresh,
    ),
  ],
  addHistory: {
    '葱': {'count': 3, 'category': '蔬菜', 'storage': 'fridge', 'unit': '把'},
  },
  shopping: [
    ShoppingItem.fromJson({'id': 'si_1', 'name': '酱油', 'category': '调料'}),
  ],
  customRecipes: [
    Recipe.fromJson({
      'id': 'r_1',
      'name': '番茄炒蛋',
      'ingredients': [],
      'steps': ['打蛋'],
    }),
  ],
  aiSettings: _aiSettings,
);

void main() {
  test('import restores every section into the live stores + Drift', () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
      ],
    );
    addTearDown(container.dispose);

    await container.read(backupControllerProvider).import(_fullBackup());

    // Live notifier state reflects the restore.
    expect(container.read(inventoryProvider).map((i) => i.name), contains('番茄'));
    expect(container.read(shoppingProvider).map((s) => s.name), contains('酱油'));
    expect(
      container.read(customRecipesProvider).map((r) => r.name),
      contains('番茄炒蛋'),
    );
    expect(container.read(addHistoryProvider).map((f) => f.name), contains('葱'));
    expect(container.read(aiSettingsProvider), _aiSettings);

    // And it actually landed on disk (a fresh repo read sees it), proving the
    // restore goes through the live Drift store, not orphaned prefs blobs.
    final persisted = await InventoryRepo(db).loadAllFor('');
    expect(persisted.map((i) => i.name), contains('番茄'));
  });

  test('import surfaces a persistence failure instead of reporting success',
      () async {
    final db = newTestDatabase();
    addTearDown(db.close);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...testStorageOverrides(database: db),
        // Force the restore write to fail so we can assert it propagates.
        inventoryRepoProvider.overrideWithValue(_ThrowingInventoryRepo(db)),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(backupControllerProvider).import(_fullBackup()),
      throwsA(anything),
    );
  });
}

/// An [InventoryRepo] whose write fails, to prove a failed restore propagates
/// out of [BackupController.import] instead of being swallowed.
class _ThrowingInventoryRepo extends InventoryRepo {
  _ThrowingInventoryRepo(super.db);

  @override
  Future<void> saveItems(String householdId, List<Ingredient> items) async {
    throw StateError('simulated disk write failure');
  }
}
