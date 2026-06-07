import 'package:drift/drift.dart';

import '../models/food_log_entry.dart';
import 'drift/app_database.dart';
import 'drift/entity_row_codec.dart';

/// Local persistence for the append-only food-departure log, scoped by household.
///
/// Mirrors [MealPlanRepo]: a one-shot hydrated seed keeps the stats notifier's
/// `build()` synchronous, while household switches reload via [loadRecentFor].
///
/// Unlike the bounded weekly plan, this log grows unbounded over time, so the
/// stats path reads a **recent window** ([loadRecentFor]); [loadAllFor] stays
/// available for backup/sync completeness.
class FoodLogRepo {
  FoodLogRepo(this._db);

  final AppDatabase _db;
  List<FoodLogEntry>? _hydratedSeed;

  /// Pre-read seed (injected by main.dart) so the notifier's `build()` can stay
  /// synchronous while reads from Drift are async.
  void hydrate(List<FoodLogEntry> seed) => _hydratedSeed = seed;

  /// Returns the hydrated seed once; falls back to empty when none is set
  /// (household switches load via the async loaders).
  List<FoodLogEntry> loadAll() {
    final seed = _hydratedSeed;
    _hydratedSeed = null;
    return seed ?? const [];
  }

  /// Appends one departure event. No-op on a blank id (never write an
  /// unidentifiable row that sync/backup can't address).
  Future<void> append(String householdId, FoodLogEntry entry) async {
    if (entry.id.isEmpty) return;
    await _db
        .into(_db.foodLogEntries)
        .insert(
          foodLogCompanionFor(householdId, entry),
          mode: InsertMode.insertOrReplace,
        );
  }

  Future<List<FoodLogEntry>> loadAllFor(String householdId) async {
    final rows = await (_db.select(
      _db.foodLogEntries,
    )..where((t) => t.householdId.equals(householdId))).get();
    return _decode(rows);
  }

  /// Bounded load for the stats window — only rows logged at/after [sinceMs].
  Future<List<FoodLogEntry>> loadRecentFor(
    String householdId, {
    required int sinceMs,
  }) async {
    final rows =
        await (_db.select(_db.foodLogEntries)..where(
              (t) =>
                  t.householdId.equals(householdId) &
                  t.loggedAt.isBiggerOrEqualValue(sinceMs),
            ))
            .get();
    return _decode(rows);
  }

  List<FoodLogEntry> _decode(List<FoodLogRow> rows) {
    final entries = <FoodLogEntry>[];
    for (final row in rows) {
      try {
        final entry = foodLogFromRow(row);
        if (entry.id.isNotEmpty) entries.add(entry);
      } catch (_) {
        // skip malformed (e.g. missing/unparseable loggedAt)
      }
    }
    return entries;
  }

  /// 删除某一条记录(误记/删除被撤销时反转日志,避免「幽灵」浪费统计)。
  /// 定点删,绝不能用 saveEntries 重写整 scope——那会连带丢掉窗口外的历史行。
  Future<void> deleteEntry(String householdId, String id) {
    return (_db.delete(_db.foodLogEntries)..where(
          (t) => t.householdId.equals(householdId) & t.id.equals(id),
        ))
        .go();
  }

  /// 删除某 household 作用域的全部行(接管本地数据后清除 `''` 原始行)。
  Future<void> deleteHouseholdScope(String householdId) {
    return (_db.delete(
      _db.foodLogEntries,
    )..where((t) => t.householdId.equals(householdId))).go();
  }

  /// Replace-all for a scope (sync apply / backup import).
  Future<void> saveEntries(String householdId, List<FoodLogEntry> entries) {
    return _db.transaction(() async {
      await (_db.delete(
        _db.foodLogEntries,
      )..where((t) => t.householdId.equals(householdId))).go();
      await _db.batch((b) {
        b.insertAll(
          _db.foodLogEntries,
          entries
              .where((e) => e.id.isNotEmpty)
              .map((e) => foodLogCompanionFor(householdId, e)),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }
}
