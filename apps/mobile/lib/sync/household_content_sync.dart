import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../providers/custom_recipe_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';
import 'sync_providers.dart';

class HouseholdContentSync extends ConsumerStatefulWidget {
  const HouseholdContentSync({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<HouseholdContentSync> createState() =>
      _HouseholdContentSyncState();
}

class _HouseholdContentSyncState extends ConsumerState<HouseholdContentSync> {
  final _subscriptions = <StreamSubscription<List<Map<String, dynamic>>>>[];
  String _activeHouseholdId = '';
  int _generation = 0;

  @override
  void dispose() {
    _cancelSubscriptions();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final householdId = ref.watch(selectedHouseholdIdProvider).trim();
    if (householdId != _activeHouseholdId) {
      _activeHouseholdId = householdId;
      _generation += 1;
      final generation = _generation;
      _cancelSubscriptions();
      if (householdId.isNotEmpty) {
        Future.microtask(() => _startSync(householdId, generation));
      }
    }
    return widget.child;
  }

  Future<void> _startSync(String householdId, int generation) async {
    try {
      await ref.read(syncPushPendingProvider)();
      final remote = ref.read(remotePantryRepositoryProvider);
      _subscribeToRemote(remote, householdId, generation);

      final inventoryRows = await remote.loadInventory(householdId);
      final shoppingRows = await remote.loadShopping(householdId);
      final customRecipeRows = await remote.loadCustomRecipes(householdId);
      if (!_isCurrent(generation, householdId)) return;

      await _applyInventoryRows(inventoryRows);
      await _applyShoppingRows(shoppingRows);
      await _applyCustomRecipeRows(customRecipeRows);
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

  void _subscribeToRemote(
    RemotePantryRepository remote,
    String householdId,
    int generation,
  ) {
    _subscriptions
      ..add(
        remote.watchInventory(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyInventoryRows(rows));
        }, onError: _reportStreamError),
      )
      ..add(
        remote.watchShopping(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyShoppingRows(rows));
        }, onError: _reportStreamError),
      )
      ..add(
        remote.watchCustomRecipes(householdId).listen((rows) {
          if (!_isCurrent(generation, householdId)) return;
          unawaited(_applyCustomRecipeRows(rows));
        }, onError: _reportStreamError),
      );
  }

  Future<void> _applyInventoryRows(List<Map<String, dynamic>> rows) {
    final items = visibleRemoteRows(rows)
        .map(Ingredient.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
        .toList(growable: false);
    return ref.read(inventoryProvider.notifier).replaceFromRemote(items);
  }

  Future<void> _applyShoppingRows(List<Map<String, dynamic>> rows) {
    final items = visibleRemoteRows(rows)
        .map(ShoppingItem.fromJson)
        .where((item) => item.id.isNotEmpty && item.name.trim().isNotEmpty)
        .toList(growable: false);
    return ref.read(shoppingProvider.notifier).replaceFromRemote(items);
  }

  Future<void> _applyCustomRecipeRows(List<Map<String, dynamic>> rows) {
    final recipes = visibleRemoteRows(rows)
        .map(Recipe.fromJson)
        .where(
          (recipe) => recipe.id.isNotEmpty && recipe.name.trim().isNotEmpty,
        )
        .toList(growable: false);
    return ref.read(customRecipesProvider.notifier).replaceFromRemote(recipes);
  }

  bool _isCurrent(int generation, String householdId) {
    return mounted &&
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
