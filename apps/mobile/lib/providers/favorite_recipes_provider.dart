import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/favorite_recipes_repo.dart';
import 'storage_service_provider.dart';

const favoriteRecipesStorageKey = FavoriteRecipesRepo.storageKey;

/// Repo provider, wired through the shared [storageAdapterProvider] like the
/// other storage-backed repos (see `storage_service_provider.dart`).
final favoriteRecipesRepoProvider = Provider<FavoriteRecipesRepo>((ref) {
  return FavoriteRecipesRepo(ref.read(storageAdapterProvider));
});

/// Holds the set of favorited recipe ids. Loads from the repo in [build] and
/// persists on every mutation — mirrors [AiSettingsNotifier].
class FavoriteRecipesNotifier extends Notifier<Set<String>> {
  late FavoriteRecipesRepo _repo;

  @override
  Set<String> build() {
    _repo = ref.read(favoriteRecipesRepoProvider);
    return _repo.load();
  }

  bool isFavorite(String recipeId) => state.contains(recipeId);

  Future<void> toggle(String recipeId) async {
    if (recipeId.isEmpty) return;
    final next = Set<String>.from(state);
    if (!next.add(recipeId)) {
      next.remove(recipeId);
    }
    state = next;
    _repo.save(next);
  }
}

final favoriteRecipesProvider =
    NotifierProvider<FavoriteRecipesNotifier, Set<String>>(
      FavoriteRecipesNotifier.new,
    );

/// Convenience derived provider: whether a specific recipe id is favorited.
final isRecipeFavoriteProvider = Provider.family<bool, String>((ref, recipeId) {
  return ref.watch(favoriteRecipesProvider).contains(recipeId);
});
