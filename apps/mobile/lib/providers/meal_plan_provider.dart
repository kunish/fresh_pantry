import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../storage/meal_plan_repo.dart';
import '../sync/sync_enqueue.dart';
import '../sync/sync_ids.dart';
import '../sync/sync_operation.dart';
import '_persistence_queue.dart';
import 'custom_recipe_provider.dart';
import 'inventory_provider.dart';
import 'recipe_provider.dart';
import 'storage_service_provider.dart';

/// Weekly meal-plan state, persisted to Drift (household-scoped) and synced.
///
/// Mixes in [SyncEnqueue]: every mutation records a sync op in the outbox via
/// [enqueueSync], which no-ops when the app is local-only (no household). The
/// matching Supabase table + gateway/codec wiring land together (migration
/// `..._meal_plan_entries_sync.sql`), so an enqueued op always has a remote home.
class MealPlanNotifier extends Notifier<List<MealPlanEntry>>
    with PersistenceQueue, SyncEnqueue<List<MealPlanEntry>> {
  late MealPlanRepo _repo;

  @override
  SyncEntityType get syncEntityType => SyncEntityType.mealPlanEntry;

  @override
  List<MealPlanEntry> build() {
    _repo = ref.read(mealPlanRepoProvider);
    return _repo.loadAll();
  }

  Future<void> _save(List<MealPlanEntry> entries) =>
      _repo.saveEntries(activeHouseholdId, entries);

  /// 下拉刷新：从本地 DB(按当前 household)重读。用 reload 而非
  /// `ref.invalidate`——build() 的种子是一次性的(读完即清),重建只会落回空列表。
  Future<void> reload() async {
    state = await _repo.loadAllFor(activeHouseholdId);
  }

  Future<void> replaceFromRemote(
    List<MealPlanEntry> entries, {
    bool rethrowOnError = false,
  }) {
    return queuePersistence(() async {
      await _save(entries);
      state = entries;
    }, rethrowError: rethrowOnError);
  }

  Future<void> _mutate(
    List<MealPlanEntry> Function(List<MealPlanEntry>) nextState,
  ) {
    return queuePersistence(() async {
      final current = state;
      final next = nextState(current);
      if (identical(next, current)) return;
      await _save(next);
      state = next;
    });
  }

  /// 把一道菜计划到某一天,返回新建条目的 id。
  Future<String> addEntry({
    required DateTime date,
    required Recipe recipe,
    int servings = 1,
  }) async {
    final entry = MealPlanEntry(
      id: newSyncEntityId(),
      date: date,
      recipeId: recipe.id,
      recipeName: recipe.name,
      recipeImageUrl: recipe.imageUrl,
      servings: servings < 1 ? 1 : servings,
    );
    await _mutate((current) => [...current, entry]);
    await enqueueSync(
      entityId: entry.id,
      operation: SyncOperationType.create,
      patch: entry.toJson(),
    );
    return entry.id;
  }

  Future<void> remove(String id) async {
    if (id.isEmpty) return;
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final removed = state[index];
    await _mutate((current) => current.where((e) => e.id != id).toList());
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: removed.remoteVersion,
    );
  }

  Future<void> setDone(String id, bool done) =>
      _updateById(id, (e) => e.copyWith(done: done));

  Future<void> moveToDate(String id, DateTime date) =>
      _updateById(id, (e) => e.copyWith(date: MealPlanEntry.dateOnly(date)));

  Future<void> _updateById(
    String id,
    MealPlanEntry Function(MealPlanEntry) transform,
  ) async {
    if (id.isEmpty) return;
    final index = state.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final original = state[index];
    final updated = transform(original);
    await _mutate((current) {
      final i = current.indexWhere((e) => e.id == id);
      if (i == -1) return current;
      final next = [...current];
      next[i] = updated;
      return next;
    });
    await enqueueSync(
      entityId: id,
      operation: SyncOperationType.update,
      patch: updated.toJson(),
      baseVersion: original.remoteVersion,
    );
  }
}

final mealPlanProvider =
    NotifierProvider<MealPlanNotifier, List<MealPlanEntry>>(
      MealPlanNotifier.new,
    );

/// Entries grouped by day (date-only key), insertion order preserved per day.
/// The calendar UI reads this to lay out each day's planned meals.
final mealPlanByDayProvider = Provider<Map<DateTime, List<MealPlanEntry>>>((
  ref,
) {
  final entries = ref.watch(mealPlanProvider);
  final byDay = <DateTime, List<MealPlanEntry>>{};
  for (final entry in entries) {
    byDay.putIfAbsent(entry.date, () => []).add(entry);
  }
  return byDay;
});

/// Distinct ingredient names required by not-yet-cooked planned meals that the
/// inventory doesn't already cover — the shopping "缺料" set, ready to feed
/// `shoppingProvider.addFromSuggestion`.
///
/// Each entry's recipe is resolved from the preset library + custom recipes
/// (custom shadows a preset on id clash). Entries whose recipe can no longer be
/// found contribute nothing — a deleted recipe gives no ingredient list to
/// reason about, and inventing needs would be worse than surfacing none.
/// Matching reuses [recipeIngredientMatchesInventory] so it stays consistent
/// with the recipe-discovery screens (substring match, case-insensitive).
final mealPlanMissingIngredientsProvider = Provider<List<String>>((ref) {
  final pending = ref
      .watch(mealPlanProvider)
      .where((entry) => !entry.done)
      .toList();
  if (pending.isEmpty) return const [];

  final recipeById = <String, Recipe>{};
  final presets = ref
      .watch(recipesProvider)
      .maybeWhen(data: (data) => data, orElse: () => const <Recipe>[]);
  for (final recipe in presets) {
    recipeById[recipe.id] = recipe;
  }
  for (final recipe in ref.watch(customRecipesProvider)) {
    recipeById[recipe.id] = recipe;
  }

  final inventoryNames = inventoryNameSet(ref.watch(inventoryProvider));

  final seen = <String>{};
  final missing = <String>[];
  for (final entry in pending) {
    final recipe = recipeById[entry.recipeId];
    if (recipe == null) continue;
    for (final ingredient in recipe.ingredients) {
      final name = ingredient.name.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.contains(key)) continue;
      if (recipeIngredientMatchesInventory(ingredient, inventoryNames)) {
        continue;
      }
      seen.add(key);
      missing.add(name);
    }
  }
  return missing;
});

/// At-a-glance weekly snapshot for the Dashboard entry card.
///
/// - [upcoming]: meals planned within the rolling 7-day window `[today, +7)`
///   (past meals and ones further out are excluded — the card is about *this*
///   week).
/// - [today]: how many of those fall on today.
/// - [missing]: distinct ingredients the not-yet-cooked plans still need,
///   reused verbatim from [mealPlanMissingIngredientsProvider] (single source of
///   truth — the card only routes to the screen that resolves the shortfall).
typedef MealPlanWeekSummary = ({int upcoming, int today, int missing});

final mealPlanWeekSummaryProvider = Provider<MealPlanWeekSummary>((ref) {
  final today = MealPlanEntry.dateOnly(DateTime.now());
  final windowEnd = today.add(const Duration(days: 7));
  var upcoming = 0;
  var todayCount = 0;
  for (final entry in ref.watch(mealPlanProvider)) {
    if (entry.date.isBefore(today) || !entry.date.isBefore(windowEnd)) continue;
    upcoming++;
    if (entry.date == today) todayCount++;
  }
  return (
    upcoming: upcoming,
    today: todayCount,
    missing: ref.watch(mealPlanMissingIngredientsProvider).length,
  );
});
