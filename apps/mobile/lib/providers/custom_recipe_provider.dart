import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/_persistence_queue.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/sync/sync_enqueue.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';

class CustomRecipeNotifier extends Notifier<List<Recipe>>
    with PersistenceQueue, SyncEnqueue<List<Recipe>> {
  late CustomRecipeRepo _repo;

  @override
  SyncEntityType get syncEntityType => SyncEntityType.customRecipe;

  @override
  List<Recipe> build() {
    _repo = ref.read(customRecipeRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _save(List<Recipe> recipes) async {
    await _repo.saveRecipes(activeHouseholdId, recipes);
  }

  Future<void> _mutate(List<Recipe> Function(List<Recipe>) nextState) {
    return queuePersistence(() async {
      final current = state;
      final next = nextState(current);
      if (identical(next, current)) {
        return;
      }

      await _save(next);
      state = next;
    });
  }

  Recipe _withSyncId(Recipe recipe) {
    final id = syncIdFor(recipe.id);
    return id == recipe.id ? recipe : recipe.copyWith(id: id);
  }

  /// Collapses duplicate ingredient names (e.g. 味精 entered twice) before a
  /// recipe is persisted and synced. Mirrors the load-time dedup in
  /// `Recipe.fromJson` so the in-memory list shown right after save matches what
  /// a reload would yield.
  Recipe _dedupeIngredients(Recipe recipe) {
    final deduped = dedupeRecipeIngredients(recipe.ingredients);
    return deduped.length == recipe.ingredients.length
        ? recipe
        : recipe.copyWith(ingredients: deduped);
  }

  /// Replaces the whole list and persists it. [rethrowOnError] false for the
  /// sync inflow (swallow + retry); backup restore passes true so a failed
  /// write surfaces instead of falsely reporting success. State is set only
  /// after the write lands, so a failure leaves the prior list intact.
  Future<void> replaceFromRemote(
    List<Recipe> recipes, {
    bool rethrowOnError = false,
  }) {
    return queuePersistence(() async {
      await _save(recipes);
      state = recipes;
    }, rethrowError: rethrowOnError);
  }

  Future<void> add(Recipe recipe) async {
    final recipeToAdd = _dedupeIngredients(_withSyncId(recipe));
    if (recipeToAdd.id.isEmpty || recipeToAdd.name.isEmpty) {
      return;
    }

    await _mutate((current) => [...current, recipeToAdd]);
    await enqueueSync(
      entityId: recipeToAdd.id,
      operation: SyncOperationType.create,
      patch: recipeToAdd.toJson(),
    );
  }

  Future<void> update(String id, Recipe recipe) async {
    if (id.isEmpty || recipe.name.isEmpty) {
      return;
    }

    final originalIndex = state.indexWhere((saved) => saved.id == id);
    if (originalIndex == -1) {
      return;
    }
    final original = state[originalIndex];
    final updatedRecipe = _dedupeIngredients(recipe.copyWith(id: id));
    await _mutate((current) {
      final index = current.indexWhere((saved) => saved.id == id);
      final next = [...current];
      next[index] = updatedRecipe;
      return next;
    });
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.update,
      patch: updatedRecipe.toJson(),
      baseVersion: original.remoteVersion,
    );
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) {
      return;
    }

    final originalIndex = state.indexWhere((recipe) => recipe.id == id);
    if (originalIndex == -1) {
      return;
    }
    final original = state[originalIndex];
    await _mutate((current) {
      final next = current.where((recipe) => recipe.id != id).toList();
      return next;
    });
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: original.remoteVersion,
    );
  }
}

final customRecipesProvider =
    NotifierProvider<CustomRecipeNotifier, List<Recipe>>(
      CustomRecipeNotifier.new,
    );
