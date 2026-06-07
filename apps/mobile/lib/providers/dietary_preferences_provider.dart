import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/dietary_preferences_repo.dart';
import 'storage_service_provider.dart';

/// Repo provider, wired through the shared [storageAdapterProvider] like the
/// other storage-backed repos (see `storage_service_provider.dart`).
final dietaryPreferencesRepoProvider = Provider<DietaryPreferencesRepo>((ref) {
  return DietaryPreferencesRepo(ref.read(storageAdapterProvider));
});

/// Holds the set of avoided-ingredient keywords (忌口). Loads from the repo in
/// [build] and persists on every mutation — mirrors [FavoriteRecipesNotifier].
///
/// Keywords are normalized (trim + lowercase) on the way in so this notifier is
/// the single source of the stored form and the matcher can compare directly.
class DietaryExclusionsNotifier extends Notifier<Set<String>> {
  late DietaryPreferencesRepo _repo;

  @override
  Set<String> build() {
    _repo = ref.read(dietaryPreferencesRepoProvider);
    return _repo.load();
  }

  Future<void> add(String keyword) async {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty || state.contains(normalized)) return;
    final next = {...state, normalized};
    state = next;
    _repo.save(next);
  }

  Future<void> remove(String keyword) async {
    if (!state.contains(keyword)) return;
    final next = {...state}..remove(keyword);
    state = next;
    _repo.save(next);
  }
}

final dietaryExclusionsProvider =
    NotifierProvider<DietaryExclusionsNotifier, Set<String>>(
      DietaryExclusionsNotifier.new,
    );
