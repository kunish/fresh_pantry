import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../storage/ai_settings_repo.dart';
import '../storage/custom_recipe_repo.dart';
// The drift-generated row data class is also named `ShoppingItem`, colliding
// with the model import above. This file only needs `AppDatabase`.
import '../storage/drift/app_database.dart' hide ShoppingItem;
import '../storage/inventory_repo.dart';
import '../storage/shared_prefs_storage_adapter.dart';
import '../storage/shopping_repo.dart';
import '../storage/storage_adapter.dart';
import '../sync/sync_outbox_repo.dart';

/// The Drift database backing all structured persistence.
///
/// Throws by default — must be overridden with an [AppDatabase] in `main()`
/// (and in tests with an in-memory database). Repos read it from here so the
/// whole persistence layer shares a single connection.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'appDatabaseProvider must be overridden with an AppDatabase in main().',
  );
});

/// Optional startup/test seed for inventory. When overridden, the repo hydrates
/// from this list instead of reading storage on first load.
final inventorySeedProvider = Provider<List<Ingredient>?>((ref) => null);

/// Optional startup/test seed for shopping.
final shoppingSeedProvider = Provider<List<ShoppingItem>?>((ref) => null);

/// Optional startup/test seed for custom recipes.
final customRecipeSeedProvider = Provider<List<Recipe>?>((ref) => null);

/// Provider for the storage adapter.
///
/// Falls back to [sharedPreferencesProvider] if not overridden — this allows
/// existing tests that only override [sharedPreferencesProvider] to keep
/// working without changes. Production code should override this directly
/// via [ProviderScope] overrides in `main()`. Still used by settings/cache
/// repos that have not migrated to Drift.
final storageAdapterProvider = Provider<StorageAdapter>((ref) {
  try {
    final prefs = ref.read(sharedPreferencesProvider);
    return SharedPrefsStorageAdapter(prefs);
  } catch (_) {
    throw UnimplementedError(
      'Either storageAdapterProvider must be overridden, '
      'or sharedPreferencesProvider must be available as fallback.',
    );
  }
});

final inventoryRepoProvider = Provider<InventoryRepo>((ref) {
  final repo = InventoryRepo(ref.read(appDatabaseProvider));
  final seed = ref.read(inventorySeedProvider);
  if (seed != null) {
    repo.hydrate(seed);
  }
  return repo;
});

final shoppingRepoProvider = Provider<ShoppingRepo>((ref) {
  final repo = ShoppingRepo(ref.read(appDatabaseProvider));
  final seed = ref.read(shoppingSeedProvider);
  if (seed != null) {
    repo.hydrate(seed);
  }
  return repo;
});

final customRecipeRepoProvider = Provider<CustomRecipeRepo>((ref) {
  final repo = CustomRecipeRepo(ref.read(appDatabaseProvider));
  final seed = ref.read(customRecipeSeedProvider);
  if (seed != null) {
    repo.hydrate(seed);
  }
  return repo;
});

final aiSettingsRepoProvider = Provider<AiSettingsRepo>((ref) {
  return AiSettingsRepo(ref.read(storageAdapterProvider));
});

final syncOutboxRepoProvider = Provider<SyncOutboxRepo>((ref) {
  return SyncOutboxRepo(ref.read(appDatabaseProvider));
});

/// Provider for SharedPreferences instance.
///
/// Throws by default — must be overridden in [ProviderScope] in `main()`.
/// Kept for food_details_provider and recipe_provider which will be
/// migrated in a future ADR.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with SharedPreferences '
    'instance via ProviderScope overrides.',
  );
});
