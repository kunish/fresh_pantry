import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../providers/storage_service_provider.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';
import 'sync_ids.dart';
import 'sync_operation.dart';
import 'sync_providers.dart';

/// Owns the local⇄remote reconciliation for a household's shared content:
/// uploading local-only rows, subscribing to realtime updates, and merging
/// remote rows with still-pending local ones. Extracted from the
/// `HouseholdContentSync` widget so the orchestration has a single named owner
/// and the widget is reduced to lifecycle glue. The pure merge/scope helpers
/// live as top-level functions below and are independently unit-testable.
///
/// Held by the widget and given its [WidgetRef]; [dispose] cancels every
/// realtime subscription. Generation + active-household guards ([_isCurrent])
/// drop any in-flight result whose household has since changed or whose owner
/// was disposed, so a stale apply can never clobber the current view.
class HouseholdContentSyncCoordinator {
  HouseholdContentSyncCoordinator(this._ref);

  final WidgetRef _ref;
  final _subscriptions = <StreamSubscription<List<Map<String, dynamic>>>>[];
  String _activeHouseholdId = '';
  int _generation = 0;
  bool _disposed = false;

  /// Switches the coordinator to [householdId]. A no-op when unchanged; on a
  /// change it cancels the old subscriptions, bumps the generation, and (for a
  /// non-empty id) kicks a fresh sync on a microtask — matching the widget's
  /// previous build-time behaviour.
  void syncTo(String householdId) {
    if (householdId == _activeHouseholdId) return;
    _activeHouseholdId = householdId;
    _generation += 1;
    final generation = _generation;
    _cancelSubscriptions();
    if (householdId.isNotEmpty) {
      Future.microtask(() => _startSync(householdId, generation));
    }
  }

  void dispose() {
    _disposed = true;
    _cancelSubscriptions();
  }

  Future<void> _startSync(String householdId, int generation) async {
    try {
      final remote = _ref.read(remotePantryRepositoryProvider);
      final uploadScope = _localUploadScopeFor(householdId);
      await _uploadLocalOnlyContent(
        remote,
        householdId,
        generation,
        uploadScope,
      );
      if (!_isCurrent(generation, householdId)) return;

      await _ref.read(syncPushPendingProvider)();
      if (!_isCurrent(generation, householdId)) return;

      _subscribeToRemote(remote, householdId, generation, uploadScope);

      final inventoryRows = await remote.loadInventory(householdId);
      final shoppingRows = await remote.loadShopping(householdId);
      final customRecipeRows = await remote.loadCustomRecipes(householdId);
      if (!_isCurrent(generation, householdId)) return;

      await _applyInventoryRows(inventoryRows, uploadScope);
      await _applyShoppingRows(shoppingRows, uploadScope);
      await _applyCustomRecipeRows(customRecipeRows, uploadScope);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry.sync',
          context: ErrorDescription('while syncing household content'),
        ),
      );
    }
  }

  Future<void> _uploadLocalOnlyContent(
    RemotePantryRepository remote,
    String householdId,
    int generation,
    _LocalUploadScope uploadScope,
  ) async {
    if (!_isCurrent(generation, householdId)) return;

    var localInventory = _withInventorySyncIds(_ref.read(inventoryProvider));
    var localShopping = _withShoppingSyncIds(_ref.read(shoppingProvider));
    var localRecipes = _withRecipeSyncIds(_ref.read(customRecipesProvider));

    await _ref
        .read(inventoryProvider.notifier)
        .replaceFromRemote(localInventory);
    await _ref.read(shoppingProvider.notifier).replaceFromRemote(localShopping);
    await _ref
        .read(customRecipesProvider.notifier)
        .replaceFromRemote(localRecipes);
    if (!_isCurrent(generation, householdId)) return;

    final inventoryToUpload = localInventory
        .where(_isLocalOnlyInventoryItem)
        .map((item) => item.toJson())
        .toList(growable: false);
    final shoppingToUpload = localShopping
        .where(_isLocalOnlyShoppingItem)
        .map((item) => item.toJson())
        .toList(growable: false);
    final recipesToUpload = localRecipes
        .where(_isLocalOnlyRecipe)
        .map((recipe) => recipe.toJson())
        .toList(growable: false);
    final scopedInventoryToUpload = inventoryToUpload
        .where(
          (row) =>
              uploadScope.allows(SyncEntityType.inventoryItem, _rowId(row)),
        )
        .toList(growable: false);
    final scopedShoppingToUpload = shoppingToUpload
        .where(
          (row) => uploadScope.allows(SyncEntityType.shoppingItem, _rowId(row)),
        )
        .toList(growable: false);
    final scopedRecipesToUpload = recipesToUpload
        .where(
          (row) => uploadScope.allows(SyncEntityType.customRecipe, _rowId(row)),
        )
        .toList(growable: false);

    await remote.upsertInventory(householdId, scopedInventoryToUpload);
    if (!_isCurrent(generation, householdId)) return;
    if (scopedInventoryToUpload.isNotEmpty) {
      localInventory = _markLocalInventoryUploaded(
        localInventory,
        _rowIds(scopedInventoryToUpload),
      );
      await _ref
          .read(inventoryProvider.notifier)
          .replaceFromRemote(localInventory);
    }

    await remote.upsertShopping(householdId, scopedShoppingToUpload);
    if (!_isCurrent(generation, householdId)) return;
    if (scopedShoppingToUpload.isNotEmpty) {
      localShopping = _markLocalShoppingUploaded(
        localShopping,
        _rowIds(scopedShoppingToUpload),
      );
      await _ref
          .read(shoppingProvider.notifier)
          .replaceFromRemote(localShopping);
    }

    await remote.upsertCustomRecipes(householdId, scopedRecipesToUpload);
    if (!_isCurrent(generation, householdId)) return;
    if (scopedRecipesToUpload.isNotEmpty) {
      localRecipes = _markLocalRecipesUploaded(
        localRecipes,
        _rowIds(scopedRecipesToUpload),
      );
      await _ref
          .read(customRecipesProvider.notifier)
          .replaceFromRemote(localRecipes);
    }
  }

  void _subscribeToRemote(
    RemotePantryRepository remote,
    String householdId,
    int generation,
    _LocalUploadScope uploadScope,
  ) {
    _subscriptions
      ..add(
        remote.watchInventory(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyInventoryRows(rows, uploadScope));
        }, onError: _reportStreamError),
      )
      ..add(
        remote.watchShopping(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyShoppingRows(rows, uploadScope));
        }, onError: _reportStreamError),
      )
      ..add(
        remote.watchCustomRecipes(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyCustomRecipeRows(rows, uploadScope));
        }, onError: _reportStreamError),
      );
  }

  Future<void> _applyInventoryRows(
    List<Map<String, dynamic>> rows,
    _LocalUploadScope uploadScope,
  ) {
    final remoteItems = visibleRemoteRows(rows)
        .map(Ingredient.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
        .toList(growable: false);
    final items = _mergeRemoteInventoryWithLocalOnly(
      remoteItems,
      _ref.read(inventoryProvider),
      uploadScope,
    );
    return _ref.read(inventoryProvider.notifier).replaceFromRemote(items);
  }

  Future<void> _applyShoppingRows(
    List<Map<String, dynamic>> rows,
    _LocalUploadScope uploadScope,
  ) {
    final remoteItems = visibleRemoteRows(rows)
        .map(ShoppingItem.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
        .toList(growable: false);
    final items = _mergeRemoteShoppingWithLocalOnly(
      remoteItems,
      _ref.read(shoppingProvider),
      uploadScope,
    );
    return _ref.read(shoppingProvider.notifier).replaceFromRemote(items);
  }

  Future<void> _applyCustomRecipeRows(
    List<Map<String, dynamic>> rows,
    _LocalUploadScope uploadScope,
  ) {
    final remoteRecipes = visibleRemoteRows(rows)
        .map(Recipe.fromJson)
        .where(
          (recipe) => recipe.id.isNotEmpty && recipe.name.trim().isNotEmpty,
        )
        .toList(growable: false);
    final recipes = _mergeRemoteRecipesWithLocalOnly(
      remoteRecipes,
      _ref.read(customRecipesProvider),
      uploadScope,
    );
    return _ref.read(customRecipesProvider.notifier).replaceFromRemote(recipes);
  }

  _LocalUploadScope _localUploadScopeFor(String householdId) {
    return _LocalUploadScope(
      householdId,
      _ref.read(syncOutboxRepoProvider).loadPending(),
    );
  }

  bool _isCurrent(int generation, String householdId) {
    return !_disposed &&
        generation == _generation &&
        householdId == _activeHouseholdId;
  }

  void _cancelSubscriptions() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
  }

  void _reportStreamError(Object error, StackTrace stackTrace) {
    // Realtime channel errors (connectivity drops, close code 1002,
    // channelError) are transient: the stream subscription is not cancelled and
    // resumes once the realtime client reconnects. Surfacing them via
    // FlutterError.reportError turned every network blip into a *fatal* Sentry
    // crash (FRESH_PANTRY-7/8). Log and move on instead of reporting.
    if (error is RealtimeSubscribeException) {
      debugPrint('Household realtime channel error (transient): $error');
      return;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'fresh_pantry.sync',
        context: ErrorDescription('while listening to household content'),
      ),
    );
  }
}

List<Ingredient> _withInventorySyncIds(List<Ingredient> items) {
  return items
      .map((item) {
        if (item.id.isNotEmpty && isUuid(item.id)) return item;
        return item.copyWith(id: newSyncEntityId());
      })
      .toList(growable: false);
}

List<ShoppingItem> _withShoppingSyncIds(List<ShoppingItem> items) {
  return items
      .map((item) {
        if (item.id.isNotEmpty && isUuid(item.id)) return item;
        return item.copyWith(id: newSyncEntityId());
      })
      .toList(growable: false);
}

List<Recipe> _withRecipeSyncIds(List<Recipe> recipes) {
  return recipes
      .map((recipe) {
        if (recipe.id.isNotEmpty && isUuid(recipe.id)) return recipe;
        return recipe.copyWith(id: newSyncEntityId());
      })
      .toList(growable: false);
}

List<Ingredient> _markLocalInventoryUploaded(
  List<Ingredient> items,
  Set<String> uploadedIds,
) {
  return items
      .map((item) {
        if (!uploadedIds.contains(item.id) ||
            !_isLocalOnlyInventoryItem(item)) {
          return item;
        }
        return item.copyWith(remoteVersion: 1);
      })
      .toList(growable: false);
}

List<ShoppingItem> _markLocalShoppingUploaded(
  List<ShoppingItem> items,
  Set<String> uploadedIds,
) {
  return items
      .map((item) {
        if (!uploadedIds.contains(item.id) || !_isLocalOnlyShoppingItem(item)) {
          return item;
        }
        return item.copyWith(remoteVersion: 1);
      })
      .toList(growable: false);
}

List<Recipe> _markLocalRecipesUploaded(
  List<Recipe> recipes,
  Set<String> uploadedIds,
) {
  return recipes
      .map((recipe) {
        if (!uploadedIds.contains(recipe.id) || !_isLocalOnlyRecipe(recipe)) {
          return recipe;
        }
        return recipe.copyWith(remoteVersion: 1);
      })
      .toList(growable: false);
}

List<Ingredient> _mergeRemoteInventoryWithLocalOnly(
  List<Ingredient> remoteItems,
  List<Ingredient> localItems,
  _LocalUploadScope uploadScope,
) {
  final remoteIds = remoteItems.map((item) => item.id).toSet();
  return [
    ...remoteItems,
    ...localItems.where(
      (item) =>
          _isLocalOnlyInventoryItem(item) &&
          !remoteIds.contains(item.id) &&
          uploadScope.allows(SyncEntityType.inventoryItem, item.id),
    ),
  ];
}

List<ShoppingItem> _mergeRemoteShoppingWithLocalOnly(
  List<ShoppingItem> remoteItems,
  List<ShoppingItem> localItems,
  _LocalUploadScope uploadScope,
) {
  final remoteIds = remoteItems.map((item) => item.id).toSet();
  return [
    ...remoteItems,
    ...localItems.where(
      (item) =>
          _isLocalOnlyShoppingItem(item) &&
          !remoteIds.contains(item.id) &&
          uploadScope.allows(SyncEntityType.shoppingItem, item.id),
    ),
  ];
}

List<Recipe> _mergeRemoteRecipesWithLocalOnly(
  List<Recipe> remoteRecipes,
  List<Recipe> localRecipes,
  _LocalUploadScope uploadScope,
) {
  final remoteIds = remoteRecipes.map((recipe) => recipe.id).toSet();
  return [
    ...remoteRecipes,
    ...localRecipes.where(
      (recipe) =>
          _isLocalOnlyRecipe(recipe) &&
          !remoteIds.contains(recipe.id) &&
          uploadScope.allows(SyncEntityType.customRecipe, recipe.id),
    ),
  ];
}

bool _isLocalOnlyInventoryItem(Ingredient item) {
  return item.remoteVersion <= 0 &&
      item.deletedAt == null &&
      item.id.isNotEmpty &&
      item.name.trim().isNotEmpty;
}

bool _isLocalOnlyShoppingItem(ShoppingItem item) {
  return item.remoteVersion <= 0 &&
      item.deletedAt == null &&
      item.id.isNotEmpty &&
      item.name.trim().isNotEmpty;
}

bool _isLocalOnlyRecipe(Recipe recipe) {
  return recipe.remoteVersion <= 0 &&
      recipe.deletedAt == null &&
      recipe.id.isNotEmpty &&
      recipe.name.trim().isNotEmpty;
}

String _rowId(Map<String, dynamic> row) {
  final id = row['id'];
  return id is String ? id : '';
}

Set<String> _rowIds(List<Map<String, dynamic>> rows) {
  return rows.map(_rowId).where((id) => id.isNotEmpty).toSet();
}

class _LocalUploadScope {
  _LocalUploadScope(String householdId, List<SyncOperation> pendingOperations)
    : _householdId = householdId,
      _pendingHouseholdsByEntity = _pendingHouseholdsByEntityType(
        pendingOperations,
      );

  final String _householdId;
  final Map<SyncEntityType, Map<String, Set<String>>>
  _pendingHouseholdsByEntity;

  bool allows(SyncEntityType entityType, String entityId) {
    if (entityId.isEmpty) return false;
    final pendingHouseholds = _pendingHouseholdsByEntity[entityType]?[entityId];
    return pendingHouseholds == null ||
        pendingHouseholds.isEmpty ||
        pendingHouseholds.contains(_householdId);
  }
}

Map<SyncEntityType, Map<String, Set<String>>> _pendingHouseholdsByEntityType(
  List<SyncOperation> operations,
) {
  final result = <SyncEntityType, Map<String, Set<String>>>{};
  for (final operation in operations) {
    final entityId = operation.entityId.trim();
    final householdId = operation.householdId.trim();
    if (entityId.isEmpty || householdId.isEmpty) continue;

    final byEntity = result.putIfAbsent(operation.entityType, () => {});
    byEntity.putIfAbsent(entityId, () => <String>{}).add(householdId);
  }
  return result;
}
