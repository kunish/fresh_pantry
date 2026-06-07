import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../models/food_log_entry.dart';
import '../models/frequent_item.dart';
import '../models/ingredient.dart';
import '../models/ingredient_identity.dart';
import '../models/proposal.dart';
import '../models/storage_area.dart';
import '../data/food_categories.dart';
import '../storage/inventory_repo.dart';
import '../sync/sync_enqueue.dart';
import '../sync/sync_ids.dart';
import '../sync/sync_operation.dart';
import '../utils/ingredient_normalizer.dart';
import '../utils/quantity_text.dart';
import '_persistence_queue.dart';
import 'food_log_provider.dart';
import 'storage_service_provider.dart';

export 'storage_service_provider.dart' show inventorySeedProvider;

const inventoryFilterAll = '全部';
const inventoryFilterNotFresh = '不新鲜';

bool isNotFreshIngredient(Ingredient item) {
  return item.state == FreshnessState.expiringSoon ||
      item.state == FreshnessState.urgent ||
      item.state == FreshnessState.expired;
}

int inventoryIndexOf(List<Ingredient> items, Ingredient item) {
  final identityIndex = items.indexWhere(
    (candidate) => identical(candidate, item),
  );
  if (identityIndex != -1) return identityIndex;
  return items.indexOf(item);
}

List<Ingredient> inventoryItemsForCategory(
  List<Ingredient> items,
  String category,
) {
  if (category == inventoryFilterAll || category.isEmpty) return items;
  if (category == inventoryFilterNotFresh) {
    return items.where(isNotFreshIngredient).toList();
  }

  final normalizedCategory = FoodCategories.normalize(category);
  return items
      .where(
        (item) => FoodCategories.normalize(item.category) == normalizedCategory,
      )
      .toList();
}

/// Narrows [items] to a single storage area. A null [storage] means "all
/// areas" (no filter) — the inventory's default, unfiltered view.
List<Ingredient> inventoryItemsForStorage(
  List<Ingredient> items,
  IconType? storage,
) {
  if (storage == null) return items;
  return items.where((item) => item.storage == storage).toList();
}

int notFreshIngredientCount(Iterable<Ingredient> items) {
  return items.where(isNotFreshIngredient).length;
}

/// How the inventory list is ordered for display. The underlying
/// [inventoryProvider] always stays in insertion order — sorting is a
/// display-only concern, and delete/merge resolve rows by identity at apply
/// time, so reordering the view never mutates the wrong row.
enum InventorySortMode {
  /// Insertion order — the list as the user built it. The default.
  manual('默认'),

  /// Soonest-to-expire first; items without an expiry date sink to the bottom.
  /// The headline view for a waste-reduction pantry: act on what spoils next.
  expiry('临期优先');

  const InventorySortMode(this.label);

  final String label;
}

int _compareByExpiry(Ingredient a, Ingredient b) {
  final ea = a.expiryDate;
  final eb = b.expiryDate;
  if (ea == null && eb == null) return 0;
  if (ea == null) return 1; // no shelf life sinks below dated items
  if (eb == null) return -1;
  return ea.compareTo(eb);
}

/// Orders [items] for display per [mode]. Display-only: callers keep the raw
/// inventory in insertion order and resolve edits by identity, so this never
/// touches persistence or sync.
///
/// [InventorySortMode.expiry] sorts by [Ingredient.expiryDate] ascending with
/// null expiry (no shelf life) last, breaking ties by original position so the
/// order is fully deterministic ([List.sort] is not stable on its own).
List<Ingredient> sortedInventoryItems(
  List<Ingredient> items,
  InventorySortMode mode,
) {
  if (mode == InventorySortMode.manual) return items;
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final byExpiry = _compareByExpiry(a.$2, b.$2);
    return byExpiry != 0 ? byExpiry : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

class InventoryNotifier extends Notifier<List<Ingredient>>
    with PersistenceQueue, SyncEnqueue<List<Ingredient>> {
  late InventoryRepo _repo;

  @override
  SyncEntityType get syncEntityType => SyncEntityType.inventoryItem;

  @override
  List<Ingredient> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _loadConsolidated(_repo.loadAll());
  }

  /// 下拉刷新：从本地 DB(按当前 household 作用域)重读。
  ///
  /// 不能用 `ref.invalidate(inventoryProvider)`——`build()` 返回的是
  /// main.dart 启动时注入的一次性种子(`loadAll()` 读完即清空),重建时种子
  /// 已被消费,只会落回空列表(下拉刷新瞬间清空的根因)。本地 DB 才是持续的
  /// 真相源(每次增删改与 sync 都同步写盘),所以直接重读即可,且 `loadAllFor`
  /// 内部已按 `now` 重算新鲜度。
  Future<void> reload() async {
    final plan = _planConsolidation(await _repo.loadAllFor(activeHouseholdId));
    state = plan.rows;
    if (plan.removed.isNotEmpty) await _persistConsolidation(plan);
  }

  Future<void> _save(List<Ingredient> items) async {
    await _repo.saveItems(activeHouseholdId, items);
  }

  /// Every inventory item is born with a stable sync UUID — local-only or not.
  /// Blank/non-UUID ids were the root of duplicate rows: each household
  /// transition minted a *fresh* id for the same logical item, so cloning it.
  Ingredient _withSyncId(Ingredient item) {
    if (isUuid(item.id)) return item;
    return item.copyWith(id: newSyncEntityId());
  }

  /// Replaces the whole list and persists it. The sync inflow leaves
  /// [rethrowOnError] false (a failed local write is swallowed; sync retries).
  /// Backup restore passes true so a failed write rolls back and propagates —
  /// a destructive "restore complete" message must never lie about data that
  /// never reached disk.
  Future<void> replaceFromRemote(
    List<Ingredient> items, {
    bool rethrowOnError = false,
  }) async {
    final plan = _planConsolidation(
      items
          .map(normalizeInventoryIngredient)
          .map(refreshIngredientFreshness)
          .toList(growable: false),
    );
    final prior = state;
    state = plan.rows;
    try {
      await queuePersistence(
        () => _save(plan.rows),
        rethrowError: rethrowOnError,
      );
    } catch (_) {
      state = prior;
      rethrow;
    }
    // A remote/restored snapshot can still carry legacy duplicates (rows added
    // before add() learned to merge); push the de-dup back so the whole
    // household converges to one row instead of re-merging on every pull.
    await _enqueueConsolidationCleanup(plan);
  }

  /// Adds [item] to inventory and returns the resulting row.
  ///
  /// A non-perishable whose name×unit×storage matches an existing row merges
  /// into it (summing quantity) — the same ADR-0001 identity rule the Intake
  /// flow ([applyIntakeProposals]) applies — so manually adding 白糖 twice
  /// yields one row, not two. Perishables (new batch each time) and
  /// non-matching items append a new row.
  Future<Ingredient> add(Ingredient item) async {
    final normalizedItem = normalizeIngredientCategory(_withSyncId(item));
    final mergeIndex = IngredientIdentity.resolveMergeTarget(
      name: normalizedItem.name,
      unit: normalizedItem.unit,
      storage: normalizedItem.storage,
      category: normalizedItem.category,
      inventory: state,
    );

    if (mergeIndex >= 0) {
      final existing = state[mergeIndex];
      final merged = refreshIngredientFreshness(
        existing.copyWith(
          quantity: _sumQuantity(existing.quantity, normalizedItem.quantity),
        ),
      );
      await _persistAddMutation([...state]..[mergeIndex] = merged, merged);
      await enqueueSync(
        entityId: merged.id,
        operation: SyncOperationType.intake,
        patch: merged.toJson(),
        baseVersion: existing.remoteVersion,
      );
      return merged;
    }

    final stampedItem = normalizedItem.addedAt == null
        ? normalizedItem.copyWith(addedAt: DateTime.now())
        : normalizedItem;
    final itemToAdd = refreshIngredientFreshness(stampedItem);
    await _persistAddMutation([...state, itemToAdd], itemToAdd);
    await enqueueSync(
      entityId: itemToAdd.id,
      operation: SyncOperationType.create,
      patch: itemToAdd.toJson(),
    );
    return itemToAdd;
  }

  /// Optimistically applies an add/merge [updated] list, records [recorded] in
  /// the restock-frequency history, and rolls back to the prior state if the
  /// local write fails so state and disk never diverge.
  Future<void> _persistAddMutation(
    List<Ingredient> updated,
    Ingredient recorded,
  ) async {
    final prior = state;
    state = updated;
    try {
      await queuePersistence(() async {
        await _save(updated);
        await ref.read(addHistoryProvider.notifier).record(recorded);
      }, rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
  }

  /// 手动删除食材后,把补货频次记忆里对应的名称抹掉——删除即"不要了",
  /// 不该再在「库存不足」里提醒补货。仅对删除后库存里已无同名残留的名称生效
  /// (大小写/空格不敏感,与 [lowStockItemsProvider] 的判定一致),所以删掉一盒
  /// 牛奶时另一盒还在就不会误清。消费扣减/合并不走这里:吃完才是该补货的时刻。
  Future<void> _forgetRemovedNames(Iterable<String> names) async {
    final present = state.map((i) => i.name.trim().toLowerCase()).toSet();
    final vanished = <String>{
      for (final name in names)
        if (!present.contains(name.trim().toLowerCase())) name,
    };
    if (vanished.isEmpty) return;
    final history = ref.read(addHistoryProvider.notifier);
    for (final name in vanished) {
      await history.forget(name);
    }
  }

  /// Records one item leaving inventory in the food log (the waste-reduction
  /// stats source) and returns the new entry's id so the caller can reverse it
  /// if the delete is undone. Snapshots name/category and whether it was
  /// past-fresh at departure. A fresh UUID id avoids same-millisecond collisions
  /// on batch removals (and is household-sync ready).
  Future<String> _logDeparture(Ingredient item, FoodLogOutcome outcome) async {
    final id = newSyncEntityId();
    await ref
        .read(foodLogProvider.notifier)
        .record(
          FoodLogEntry(
            id: id,
            name: item.name,
            category: item.category ?? FoodCategories.other,
            outcome: outcome,
            loggedAt: DateTime.now(),
            wasExpiring: isNotFreshIngredient(item),
          ),
        );
    return id;
  }

  /// Removes one inventory row. When [outcome] is given the departure is logged
  /// to the food log and its entry id is returned, so an undo can reverse the
  /// log via [FoodLogNotifier.undoRecord]. Returns null when nothing was logged.
  Future<String?> remove(int index, {FoodLogOutcome? outcome}) async {
    if (index < 0 || index >= state.length) return null;
    final removed = state[index];
    final prior = state;
    final updated = [...state]..removeAt(index);
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
      entityId: removed.id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: removed.remoteVersion,
    );
    await _forgetRemovedNames([removed.name]);
    if (outcome == null) return null;
    return _logDeparture(removed, outcome);
  }

  /// Removes every inventory row at once (the "clear all" action). Optimistic
  /// with rollback so disk never diverges from state, then enqueues a delete per
  /// removed row so other household members see the clear too.
  Future<void> clearAll() async {
    if (state.isEmpty) return;
    final removed = state;
    final deletedAt = DateTime.now().toUtc();
    final syncOperations = removed
        .map(
          (item) => SyncEnqueueOp(
            entityId: item.id,
            operation: SyncOperationType.delete,
            patch: {'deletedAt': deletedAt.toIso8601String()},
            baseVersion: item.remoteVersion,
          ),
        )
        .toList(growable: false);
    state = const <Ingredient>[];
    try {
      await queuePersistence(
        () => _save(const <Ingredient>[]),
        rethrowError: true,
      );
    } catch (_) {
      state = removed;
      rethrow;
    }
    await enqueueSyncBatch(syncOperations);
    await _forgetRemovedNames(removed.map((item) => item.name));
  }

  /// Removes every [targets] row at once (the multi-select "batch delete").
  ///
  /// Each target is resolved to its live index by stable identity (so a
  /// reordered display list never deletes the wrong row), removed optimistically
  /// with rollback, then a delete is enqueued per row so other household members
  /// see it too. Returns each removed item with its original index (ascending,
  /// so the caller can undo by re-inserting at position) and the food-log entry
  /// id it logged under (when [outcome] was given), so undo can reverse the log.
  Future<List<({int index, Ingredient item, String? logId})>> removeMany(
    Iterable<Ingredient> targets, {
    FoodLogOutcome? outcome,
  }) async {
    final indices = <int>{};
    for (final target in targets) {
      final index = inventoryIndexOf(state, target);
      if (index != -1) indices.add(index);
    }
    if (indices.isEmpty) return const [];

    final ascending = indices.toList()..sort();
    final removed = [for (final i in ascending) (index: i, item: state[i])];

    final prior = state;
    final updated = [...state];
    for (final i in ascending.reversed) {
      updated.removeAt(i);
    }
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    final deletedAt = DateTime.now().toUtc();
    await enqueueSyncBatch([
      for (final r in removed)
        SyncEnqueueOp(
          entityId: r.item.id,
          operation: SyncOperationType.delete,
          patch: {'deletedAt': deletedAt.toIso8601String()},
          baseVersion: r.item.remoteVersion,
        ),
    ]);
    await _forgetRemovedNames(removed.map((r) => r.item.name));
    return [
      for (final r in removed)
        (
          index: r.index,
          item: r.item,
          logId: outcome == null ? null : await _logDeparture(r.item, outcome),
        ),
    ];
  }

  Future<void> insertAt(int index, Ingredient item) async {
    final updated = [...state];
    final clampedIndex = index.clamp(0, updated.length).toInt();
    final normalizedItem = normalizeInventoryIngredient(_withSyncId(item));
    updated.insert(clampedIndex, normalizedItem);
    state = updated;
    await queuePersistence(() => _save(updated));
    await enqueueSync(
      entityId: normalizedItem.id,
      operation: SyncOperationType.create,
      patch: normalizedItem.toJson(),
    );
  }

  Future<void> update(int index, Ingredient item) async {
    if (index < 0 || index >= state.length) return;
    final updated = [...state];
    final original = state[index];
    final normalizedItem = normalizeIngredientCategory(item);
    final stampedItem = normalizedItem.addedAt == null
        ? normalizedItem.copyWith(addedAt: state[index].addedAt)
        : normalizedItem;
    final updatedItem = refreshIngredientFreshness(stampedItem);
    final prior = state;
    updated[index] = updatedItem;
    state = updated;
    try {
      await queuePersistence(() => _save(updated), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await enqueueSync(
      entityId: updatedItem.id,
      operation: SyncOperationType.update,
      patch: updatedItem.toJson(),
      baseVersion: original.remoteVersion,
    );
  }

  /// Applies the selected Intake proposals and returns the set of proposal ids
  /// that were actually applied, so callers (e.g. the shopping list) only clean
  /// up the source rows whose intake really landed.
  Future<Set<String>> applyIntakeProposals(
    List<IntakeProposal> proposals,
  ) async {
    var current = [...state];
    final syncOperations = <SyncEnqueueOp>[];
    final appliedIds = <String>{};
    for (final p in proposals) {
      if (!p.selected) continue;

      // Re-resolve the merge target against the LIVE inventory by the domain
      // identity rule — never a stale positional index captured at proposal
      // time (the list can reorder, shrink, or be restored from a persisted
      // draft across launches). A perishable / non-matching item falls back to
      // a new row, which can never corrupt an unrelated row.
      final mergeIndex = p.action == IntakeAction.mergeInto
          ? IngredientIdentity.resolveMergeTarget(
              name: p.name,
              unit: p.unit,
              storage: p.storage,
              category: p.category,
              inventory: current,
            )
          : -1;

      if (mergeIndex < 0) {
        final item = _withSyncId(_ingredientFromProposal(p));
        current = [...current, item];
        syncOperations.add(
          SyncEnqueueOp(
            entityId: item.id,
            operation: SyncOperationType.create,
            patch: item.toJson(),
          ),
        );
        appliedIds.add(p.id);
        continue;
      }

      final existing = current[mergeIndex];
      final summed = _sumQuantity(existing.quantity, p.quantity);
      final updatedItem = refreshIngredientFreshness(
        existing.copyWith(quantity: summed),
      );
      current = [...current]..[mergeIndex] = updatedItem;
      syncOperations.add(
        SyncEnqueueOp(
          entityId: updatedItem.id,
          operation: SyncOperationType.intake,
          patch: updatedItem.toJson(),
          baseVersion: existing.remoteVersion,
        ),
      );
      appliedIds.add(p.id);
    }
    // Apply optimistically, then roll back if the local save fails so state and
    // disk never diverge and the Review can keep the draft for a retry.
    final prior = state;
    state = current;
    try {
      await queuePersistence(() => _save(current), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await enqueueSyncBatch(syncOperations);
    return appliedIds;
  }

  Future<void> applyDeductionProposals(
    List<DeductionProposal> proposals,
  ) async {
    var current = [...state];

    // Resolve every selected deduction to a LIVE row index by stable identity,
    // and aggregate per row so two proposals that resolve to the same row net
    // into one deduction (and one sync op) instead of double-deducting /
    // double-deleting against a stale snapshot.
    final deductByIndex = <int, double>{};
    for (final p in proposals) {
      if (!p.selected) continue;
      if (p.action == DeductionAction.skip) continue;
      final chosen = _chosenCandidate(p);
      if (chosen == null) continue;
      final amount = double.tryParse(p.deductAmount.trim());
      if (amount == null || amount <= 0) continue; // never silently deduct 0
      final index = _resolveDeductionRow(current, chosen);
      if (index < 0) {
        continue; // row gone / ambiguous -> skip the wrong-row risk
      }
      deductByIndex.update(index, (v) => v + amount, ifAbsent: () => amount);
    }

    final removalIndices = <int>{};
    final syncOperations = <SyncEnqueueOp>[];
    // Rows the deduction empties out leave inventory by being cooked/used — the
    // food log records each as a consumed departure once the write lands.
    final consumedDepartures = <Ingredient>[];
    deductByIndex.forEach((index, totalDeduct) {
      final existing = current[index];
      final existingQty = double.tryParse(existing.quantity.trim());
      // Non-numeric stock (e.g. "适量", "半盒") must not be coerced to 0 and
      // deleted — leave the row untouched rather than wiping real inventory.
      if (existingQty == null) return;
      final remaining = existingQty - totalDeduct;
      if (remaining <= 0) {
        removalIndices.add(index);
        consumedDepartures.add(existing);
        final deletedAt = DateTime.now().toUtc();
        syncOperations.add(
          SyncEnqueueOp(
            entityId: existing.id,
            operation: SyncOperationType.delete,
            patch: {'deletedAt': deletedAt.toIso8601String()},
            baseVersion: existing.remoteVersion,
          ),
        );
      } else {
        final updatedItem = refreshIngredientFreshness(
          existing.copyWith(quantity: formatQuantity(remaining)),
        );
        current[index] = updatedItem;
        syncOperations.add(
          SyncEnqueueOp(
            entityId: updatedItem.id,
            operation: SyncOperationType.deduction,
            patch: updatedItem.toJson(),
            baseVersion: existing.remoteVersion,
          ),
        );
      }
    });

    if (removalIndices.isNotEmpty) {
      final sortedDesc = removalIndices.toList()
        ..sort((a, b) => b.compareTo(a));
      for (final idx in sortedDesc) {
        current.removeAt(idx);
      }
    }
    final prior = state;
    state = List<Ingredient>.from(current);
    try {
      await queuePersistence(() => _save(state), rethrowError: true);
    } catch (_) {
      state = prior;
      rethrow;
    }
    await enqueueSyncBatch(syncOperations);
    for (final item in consumedDepartures) {
      await _logDeparture(item, FoodLogOutcome.consumed);
    }
  }

  DeductionCandidate? _chosenCandidate(DeductionProposal p) {
    for (final candidate in p.candidates) {
      if (candidate.inventoryRowIndex == p.chosenIndex) return candidate;
    }
    return null;
  }

  /// Resolves the live inventory index for a chosen deduction candidate by
  /// stable identity, defending against list reordering between proposal
  /// creation and apply. Prefers the row id (household-synced rows); for
  /// local-only rows whose id is empty, falls back to the recorded positional
  /// index guarded by the captured row name, so a deduction never lands on an
  /// unrelated row. Returns -1 when the target can no longer be identified.
  int _resolveDeductionRow(
    List<Ingredient> current,
    DeductionCandidate chosen,
  ) {
    final id = chosen.inventoryRowId.trim();
    if (id.isNotEmpty) {
      final matches = <int>[];
      for (var i = 0; i < current.length; i++) {
        if (current[i].id == id) matches.add(i);
      }
      if (matches.length == 1) return matches.first;
      // 0 or ambiguous by id -> fall through to the name-guarded index path.
    }
    final index = chosen.inventoryRowIndex;
    if (index < 0 || index >= current.length) return -1;
    final expectedName = chosen.inventoryRowName.trim().toLowerCase();
    if (expectedName.isEmpty) {
      return index; // no captured identity -> trust index
    }
    if (current[index].name.trim().toLowerCase() == expectedName) return index;
    // Index drifted; recover only if exactly one row still carries the name.
    final byName = <int>[];
    for (var j = 0; j < current.length; j++) {
      if (current[j].name.trim().toLowerCase() == expectedName) byName.add(j);
    }
    return byName.length == 1 ? byName.first : -1;
  }

  Ingredient _ingredientFromProposal(IntakeProposal p) {
    final shelf = p.shelfLifeDays;
    final addedAt = DateTime.now();
    final expiryDate = shelf == null
        ? null
        : addedAt.add(Duration(days: shelf));
    return refreshIngredientFreshness(
      normalizeIngredientCategory(
        Ingredient(
          name: p.name,
          quantity: p.quantity,
          unit: p.unit,
          imageUrl: '',
          freshnessPercent: 1.0,
          state: FreshnessState.fresh,
          category: p.category,
          storage: p.storage,
          expiryDate: expiryDate,
          addedAt: addedAt,
          shelfLifeDays: shelf,
        ),
      ),
    );
  }

  String _sumQuantity(String a, String b) {
    final na = double.tryParse(a) ?? 0;
    final nb = double.tryParse(b) ?? 0;
    return formatQuantity(na + nb);
  }

  Future<void> mergeBatch(int sourceIndex, int targetIndex) async {
    if (sourceIndex == targetIndex) return;
    if (sourceIndex < 0 || sourceIndex >= state.length) return;
    if (targetIndex < 0 || targetIndex >= state.length) return;
    final source = state[sourceIndex];
    final target = state[targetIndex];
    if (source.unit.trim() != target.unit.trim()) return;
    if (source.storage != target.storage) return;
    final summed = _sumQuantity(source.quantity, target.quantity);
    final earlierExpiry = _earlierExpiry(source.expiryDate, target.expiryDate);
    final mergedTarget = refreshIngredientFreshness(
      target.copyWith(quantity: summed, expiryDate: earlierExpiry),
    );
    final updated = [...state];
    updated[targetIndex] = mergedTarget;
    updated.removeAt(sourceIndex);
    state = updated;
    await queuePersistence(() => _save(updated));
    await enqueueSync(
      entityId: mergedTarget.id,
      operation: SyncOperationType.update,
      patch: mergedTarget.toJson(),
      baseVersion: target.remoteVersion,
    );
    final deletedAt = DateTime.now().toUtc();
    await enqueueSync(
      entityId: source.id,
      operation: SyncOperationType.delete,
      patch: {'deletedAt': deletedAt.toIso8601String()},
      baseVersion: source.remoteVersion,
    );
  }

  DateTime? _earlierExpiry(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }

  /// Consolidates a freshly loaded list for display and, when it actually merged
  /// rows, schedules the durable cleanup (persist + sync) without blocking the
  /// return, so the UI shows the de-duplicated list on the first frame and never
  /// flashes the duplicates.
  List<Ingredient> _loadConsolidated(List<Ingredient> loaded) {
    final plan = _planConsolidation(loaded);
    if (plan.removed.isNotEmpty) {
      // build() is synchronous; defer the write to a microtask. state is already
      // plan.rows (we return it below), so the persistence reads the clean list.
      Future.microtask(() => _persistConsolidation(plan));
    }
    return plan.rows;
  }

  /// Collapses rows sharing the ADR-0001 non-perishable identity
  /// (name x unit x storage) into their first occurrence, summing quantities and
  /// keeping the earlier expiry. Perishables (distinct batches) and rows with a
  /// non-numeric quantity are left untouched, the same guard
  /// [IngredientIdentity.resolveMergeTarget] applies on add. Pure: touches no
  /// state or disk. Returns the rebuilt [rows], the survivors that absorbed a
  /// duplicate ([mergedSurvivors], needing a sync update) and the dropped
  /// [removed] rows (needing a sync delete).
  ({
    List<Ingredient> rows,
    List<Ingredient> mergedSurvivors,
    List<Ingredient> removed,
  })
  _planConsolidation(List<Ingredient> items) {
    final survivors = <Ingredient>[];
    final survivorIndexByKey = <String, int>{};
    final mergedKeys = <String>{};
    final removed = <Ingredient>[];

    for (final item in items) {
      final name = item.name.trim();
      final canMerge =
          name.isNotEmpty &&
          double.tryParse(item.quantity.trim()) != null &&
          !IngredientIdentity.isPerishable(
            category: item.category,
            name: item.name,
          );
      if (!canMerge) {
        survivors.add(item);
        continue;
      }
      // NUL joins the identity parts so a name/unit containing spaces can never
      // collide with another row's key.
      final key =
          '${name.toLowerCase()}\u0000${item.unit.trim()}\u0000${item.storage}';
      final targetIndex = survivorIndexByKey[key];
      if (targetIndex == null) {
        survivorIndexByKey[key] = survivors.length;
        survivors.add(item);
        continue;
      }
      final target = survivors[targetIndex];
      survivors[targetIndex] = refreshIngredientFreshness(
        target.copyWith(
          quantity: _sumQuantity(target.quantity, item.quantity),
          expiryDate: _earlierExpiry(target.expiryDate, item.expiryDate),
        ),
      );
      mergedKeys.add(key);
      removed.add(item);
    }

    return (
      rows: survivors,
      mergedSurvivors: [
        for (final key in mergedKeys) survivors[survivorIndexByKey[key]!],
      ],
      removed: removed,
    );
  }

  /// Durably commits a consolidation [plan]: persists the current (already
  /// consolidated) state and enqueues an update per absorbed survivor and a
  /// delete per dropped row, mirroring [mergeBatch] so other household members
  /// converge. Best-effort: a write failure is swallowed (the display is already
  /// correct and the next load retries) rather than crashing startup.
  Future<void> _persistConsolidation(
    ({
      List<Ingredient> rows,
      List<Ingredient> mergedSurvivors,
      List<Ingredient> removed,
    })
    plan,
  ) async {
    try {
      await queuePersistence(() => _save(state), rethrowError: true);
      await _enqueueConsolidationCleanup(plan);
    } catch (_) {
      // Swallowed by design: the consolidated list is already shown; the next
      // load (build/reload) retries the persistence.
    }
  }

  /// Enqueues the sync deltas for a consolidation: an update per absorbed
  /// survivor and a delete per dropped row, mirroring [mergeBatch] so the server
  /// and other household members converge to the single merged row.
  Future<void> _enqueueConsolidationCleanup(
    ({
      List<Ingredient> rows,
      List<Ingredient> mergedSurvivors,
      List<Ingredient> removed,
    })
    plan,
  ) async {
    if (plan.removed.isEmpty) return;
    final deletedAt = DateTime.now().toUtc();
    await enqueueSyncBatch([
      for (final survivor in plan.mergedSurvivors)
        SyncEnqueueOp(
          entityId: survivor.id,
          operation: SyncOperationType.update,
          patch: survivor.toJson(),
          baseVersion: survivor.remoteVersion,
        ),
      for (final dropped in plan.removed)
        SyncEnqueueOp(
          entityId: dropped.id,
          operation: SyncOperationType.delete,
          patch: {'deletedAt': deletedAt.toIso8601String()},
          baseVersion: dropped.remoteVersion,
        ),
    ]);
  }
  List<Ingredient> getByCategory(String category) {
    return inventoryItemsForCategory(state, category);
  }
}

final inventoryProvider = NotifierProvider<InventoryNotifier, List<Ingredient>>(
  InventoryNotifier.new,
);

/// UI-state ViewModel over the add-history frequency memory. Holds only the
/// derived [FrequentItem] list; all raw-map decoding and the record/forget
/// merge logic live in [InventoryRepo] (the repo owns raw->domain).
class _AddHistoryNotifier extends Notifier<List<FrequentItem>> {
  late InventoryRepo _repo;

  @override
  List<FrequentItem> build() {
    _repo = ref.read(inventoryRepoProvider);
    return _repo.loadFrequentItems();
  }

  Future<void> record(Ingredient item) async {
    await _repo.recordAddition(item);
    state = _repo.loadFrequentItems();
  }

  /// 把某个名称从补货频次记忆中抹掉(手动删除食材时调用)。不存在则 no-op。
  Future<void> forget(String name) async {
    await _repo.forgetAddition(name);
    state = _repo.loadFrequentItems();
  }
}

final addHistoryProvider =
    NotifierProvider<_AddHistoryNotifier, List<FrequentItem>>(
      _AddHistoryNotifier.new,
    );

final expiringItemsProvider = Provider.autoDispose<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.where(isNotFreshIngredient).toList();
});

final recentAdditionsProvider = Provider.autoDispose<List<Ingredient>>((ref) {
  final items = ref.watch(inventoryProvider);
  return items.reversed.take(2).toList();
});

final statCountsProvider =
    Provider.autoDispose<({int total, int expiringSoon})>((ref) {
      final items = ref.watch(inventoryProvider);
      final expiringSoon = notFreshIngredientCount(items);
      return (total: items.length, expiringSoon: expiringSoon);
    });

final categoriesProvider = Provider.autoDispose<List<String>>((ref) {
  return const [inventoryFilterAll, ...FoodCategories.values];
});

final storageAreasProvider = Provider.autoDispose<List<StorageArea>>((ref) {
  final items = ref.watch(inventoryProvider);
  const maxCapacity = {
    IconType.fridge: 20,
    IconType.freezer: 20,
    IconType.pantry: 50,
  };
  final counts = {for (final type in IconType.values) type: 0};

  for (final item in items) {
    counts[item.storage] = (counts[item.storage] ?? 0) + 1;
  }

  return IconType.values.map((type) {
    final count = counts[type] ?? 0;
    final cap = maxCapacity[type]!;
    return StorageArea(
      name: storageAreaLabel(type),
      icon: type,
      itemCount: count,
      capacityPercent: (count / cap).clamp(0.0, 1.0),
    );
  }).toList();
});

final selectedCategoryProvider = StateProvider<String>(
  (ref) => inventoryFilterAll,
);

/// The storage area the inventory list is filtered to, or null for "all areas".
/// Mirrors [selectedCategoryProvider]: a second, orthogonal filter dimension
/// the user can combine with category and search (冰箱/冷冻室/食品柜).
final selectedStorageProvider = StateProvider<IconType?>((ref) => null);

/// Display ordering for the inventory list. Orthogonal to the category/storage
/// filters; persists across tab switches like [selectedStorageProvider].
final inventorySortModeProvider = StateProvider<InventorySortMode>(
  (ref) => InventorySortMode.manual,
);

final filteredByCategoryProvider = Provider.autoDispose<List<Ingredient>>((
  ref,
) {
  final category = ref.watch(selectedCategoryProvider);
  final items = ref.watch(inventoryProvider);
  return inventoryItemsForCategory(items, category);
});

final inventorySearchQueryProvider = StateProvider.autoDispose<String>(
  (ref) => '',
);

final filteredInventoryItemsProvider = Provider.autoDispose<List<Ingredient>>((
  ref,
) {
  final query = ref.watch(inventorySearchQueryProvider).trim().toLowerCase();
  // category → storage → search → sort, so the filters compose and the chosen
  // order is applied last over the narrowed set.
  final items = inventoryItemsForStorage(
    ref.watch(filteredByCategoryProvider),
    ref.watch(selectedStorageProvider),
  );
  final filtered = query.isEmpty
      ? items
      : items
            .where((item) => item.name.toLowerCase().contains(query))
            .toList();
  return sortedInventoryItems(filtered, ref.watch(inventorySortModeProvider));
});

final frequentItemsProvider = Provider.autoDispose<List<FrequentItem>>((ref) {
  final all = [...ref.watch(addHistoryProvider)];
  all.sort((a, b) => b.count.compareTo(a.count));
  return all.where((i) => i.count >= 2).take(6).toList();
});

final lowStockItemsProvider = Provider.autoDispose<List<FrequentItem>>((ref) {
  final all = ref.watch(addHistoryProvider);
  final inventory = ref.watch(inventoryProvider);
  final presentNames = inventory
      .map((i) => i.name.trim().toLowerCase())
      .toSet();

  final filtered = all
      .where((f) => f.count >= 3)
      .where((f) => !presentNames.contains(f.name.trim().toLowerCase()))
      .toList();
  filtered.sort((a, b) => b.count.compareTo(a.count));
  return filtered;
});
