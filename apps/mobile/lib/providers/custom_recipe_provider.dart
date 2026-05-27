import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/providers/_persistence_queue.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/custom_recipe_repo.dart';
import 'package:fresh_pantry/sync/sync_operation.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';
import 'package:uuid/uuid.dart';

const customRecipesStorageKey = CustomRecipeRepo.storageKey;
const _syncOperationIds = Uuid();

class CustomRecipeNotifier extends Notifier<List<Recipe>>
    with PersistenceQueue {
  late CustomRecipeRepo _repo;

  @override
  List<Recipe> build() {
    _repo = ref.read(customRecipeRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _mutate(List<Recipe> Function(List<Recipe>) nextState) {
    return queuePersistence(() async {
      final current = state;
      final next = nextState(current);
      if (identical(next, current)) {
        return;
      }

      _repo.saveRecipes(next);
      state = next;
    });
  }

  Future<void> _enqueueSync({
    required String entityId,
    required SyncOperationType operation,
    required Map<String, dynamic> patch,
    int? baseVersion,
  }) {
    final householdId = ref.read(selectedHouseholdIdProvider).trim();
    if (householdId.isEmpty || entityId.trim().isEmpty) {
      return Future.value();
    }

    return ref
        .read(syncOutboxRepoProvider)
        .enqueue(
          SyncOperation(
            id: _syncOperationIds.v4(),
            householdId: householdId,
            entityType: SyncEntityType.customRecipe,
            entityId: entityId,
            operation: operation,
            patch: patch,
            baseVersion: baseVersion,
            clientId: ref.read(syncClientIdProvider),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  Future<void> add(Recipe recipe) async {
    if (recipe.id.isEmpty || recipe.name.isEmpty) {
      return;
    }

    await _mutate((current) => [...current, recipe]);
    await _enqueueSync(
      entityId: recipe.id,
      operation: SyncOperationType.create,
      patch: recipe.toJson(),
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
    final updatedRecipe = recipe.copyWith(id: id);
    await _mutate((current) {
      final index = current.indexWhere((saved) => saved.id == id);
      final next = [...current];
      next[index] = updatedRecipe;
      return next;
    });
    await _enqueueSync(
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
    await _enqueueSync(
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
