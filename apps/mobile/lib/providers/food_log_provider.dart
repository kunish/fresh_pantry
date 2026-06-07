import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../models/food_log_entry.dart';
import '../storage/food_log_repo.dart';
import '../sync/sync_providers.dart';
import '_persistence_queue.dart';
import 'storage_service_provider.dart';

/// How far back the in-memory log window reaches. The log is append-only and
/// unbounded on disk; the notifier (and the startup seed) only hold this recent
/// slice — comfortably covering the current month the stats report on.
const foodLogRecentWindow = Duration(days: 90);

/// Append-only food-departure log state, persisted to Drift (household-scoped).
///
/// Local-first: no [SyncEnqueue] yet (household sync is a later round), so
/// mutations only touch local storage + state. Mirrors the meal-plan notifier's
/// shape — a one-shot hydrated seed keeps `build()` synchronous.
class FoodLogNotifier extends Notifier<List<FoodLogEntry>> with PersistenceQueue {
  late FoodLogRepo _repo;

  @override
  List<FoodLogEntry> build() {
    _repo = ref.read(foodLogRepoProvider);
    return _repo.loadAll();
  }

  String get _householdId => ref.read(selectedHouseholdIdProvider).trim();

  int _recentCutoffMs() =>
      DateTime.now().toUtc().subtract(foodLogRecentWindow).millisecondsSinceEpoch;

  /// Records one departure event (item left inventory, consumed or wasted).
  /// No-op on a blank id. Callers (inventory removal / cooking deduction)
  /// snapshot name/category/wasExpiring at the moment of departure.
  Future<void> record(FoodLogEntry entry) {
    if (entry.id.isEmpty) return Future.value();
    return queuePersistence(() async {
      await _repo.append(_householdId, entry);
      state = [...state, entry];
    });
  }

  /// Reverses a just-recorded departure (the user undid the delete that logged
  /// it). Targeted delete so an undo never corrupts the wider history; no-op on
  /// a blank id or one that's no longer in the window.
  Future<void> undoRecord(String id) {
    if (id.isEmpty) return Future.value();
    return queuePersistence(() async {
      await _repo.deleteEntry(_householdId, id);
      state = state.where((e) => e.id != id).toList();
    });
  }

  /// Reload the recent window from local DB (pull-to-refresh / household switch).
  /// Uses [loadRecentFor] not `ref.invalidate`: build()'s seed is one-shot.
  Future<void> reload() async {
    state = await _repo.loadRecentFor(_householdId, sinceMs: _recentCutoffMs());
  }

  /// Replace the local snapshot for the active scope (sync apply / backup import).
  Future<void> replaceFromRemote(
    List<FoodLogEntry> entries, {
    bool rethrowOnError = false,
  }) {
    return queuePersistence(() async {
      await _repo.saveEntries(_householdId, entries);
      state = entries;
    }, rethrowError: rethrowOnError);
  }
}

final foodLogProvider = NotifierProvider<FoodLogNotifier, List<FoodLogEntry>>(
  FoodLogNotifier.new,
);

/// Aggregate waste-reduction outcome over a window: how many items were used up
/// vs thrown away, and how many of the used ones were rescued from going bad.
class FoodLogStats {
  const FoodLogStats({this.consumed = 0, this.wasted = 0, this.rescued = 0});

  /// Items finished/used.
  final int consumed;

  /// Items thrown away.
  final int wasted;

  /// Consumed items that were already expiring/expired — waste actively avoided.
  final int rescued;

  int get total => consumed + wasted;

  /// Share of departures that were wasted, 0 when nothing was recorded.
  double get wasteRate => total == 0 ? 0 : wasted / total;

  bool get isEmpty => total == 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FoodLogStats &&
          runtimeType == other.runtimeType &&
          consumed == other.consumed &&
          wasted == other.wasted &&
          rescued == other.rescued;

  @override
  int get hashCode => Object.hash(consumed, wasted, rescued);
}

/// Pure aggregation over the entries logged at/after [since].
FoodLogStats computeFoodLogStats(
  Iterable<FoodLogEntry> entries, {
  required DateTime since,
}) {
  final sinceUtc = since.toUtc();
  var consumed = 0;
  var wasted = 0;
  var rescued = 0;
  for (final e in entries) {
    if (e.loggedAt.isBefore(sinceUtc)) continue;
    if (e.isConsumed) {
      consumed++;
      if (e.wasExpiring) rescued++;
    } else {
      wasted++;
    }
  }
  return FoodLogStats(consumed: consumed, wasted: wasted, rescued: rescued);
}

/// Local calendar-month start (1st at midnight) — the window users think in
/// ("本月我浪费了几样").
DateTime _monthStart() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
}

/// User-selectable window for the waste-insights screen. The longest option is
/// capped at [foodLogRecentWindow] so a query never reaches past the in-memory
/// slice (only the recent window is hydrated).
enum WasteStatsWindow {
  thisMonth('本月'),
  last30Days('近 30 天'),
  last90Days('近 90 天');

  const WasteStatsWindow(this.label);

  final String label;

  /// Inclusive lower bound (local time) for entries counted in this window.
  DateTime since() => switch (this) {
    WasteStatsWindow.thisMonth => _monthStart(),
    WasteStatsWindow.last30Days => DateTime.now().subtract(
      const Duration(days: 30),
    ),
    WasteStatsWindow.last90Days => DateTime.now().subtract(foodLogRecentWindow),
  };
}

/// Selected window for the insights screen (defaults to 本月). Persists across
/// navigation, like the inventory filter selections.
final wasteStatsWindowProvider = StateProvider<WasteStatsWindow>(
  (ref) => WasteStatsWindow.thisMonth,
);

/// This-month waste-reduction stats — the Dashboard card headline (fixed window).
final foodLogMonthStatsProvider = Provider<FoodLogStats>((ref) {
  return computeFoodLogStats(ref.watch(foodLogProvider), since: _monthStart());
});

/// Waste-reduction stats over the user-selected [wasteStatsWindowProvider] —
/// the insights screen headline (the Dashboard card stays on 本月).
final foodLogWindowStatsProvider = Provider<FoodLogStats>((ref) {
  final window = ref.watch(wasteStatsWindowProvider);
  return computeFoodLogStats(ref.watch(foodLogProvider), since: window.since());
});

/// (category, count) of items wasted this month, most-wasted first — the
/// "哪类最常被浪费" insight.
typedef FoodLogCategoryCount = ({String category, int count});

/// Pure: (category, count) of wasted items logged at/after [since], most-wasted
/// first. Shared by the fixed-month and windowed providers so the two never
/// diverge.
List<FoodLogCategoryCount> foodLogWastedByCategory(
  Iterable<FoodLogEntry> entries, {
  required DateTime since,
}) {
  final sinceUtc = since.toUtc();
  final counts = <String, int>{};
  for (final e in entries) {
    if (!e.isWasted || e.loggedAt.isBefore(sinceUtc)) continue;
    counts.update(e.category, (v) => v + 1, ifAbsent: () => 1);
  }
  final list = counts.entries
      .map((e) => (category: e.key, count: e.value))
      .toList();
  list.sort((a, b) => b.count.compareTo(a.count));
  return list;
}

final foodLogWastedByCategoryProvider = Provider<List<FoodLogCategoryCount>>((
  ref,
) {
  return foodLogWastedByCategory(
    ref.watch(foodLogProvider),
    since: _monthStart(),
  );
});

/// Wasted-by-category over the user-selected [wasteStatsWindowProvider].
final foodLogWastedByCategoryForWindowProvider =
    Provider<List<FoodLogCategoryCount>>((ref) {
      final window = ref.watch(wasteStatsWindowProvider);
      return foodLogWastedByCategory(
        ref.watch(foodLogProvider),
        since: window.since(),
      );
    });
