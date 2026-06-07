import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/providers/food_log_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart' show AppDatabase;

import 'support/test_database.dart';

FoodLogEntry _entry({
  required String id,
  FoodLogOutcome outcome = FoodLogOutcome.consumed,
  DateTime? loggedAt,
  String name = '番茄',
  String category = FoodCategories.freshProduce,
  bool wasExpiring = false,
}) => FoodLogEntry(
  id: id,
  name: name,
  category: category,
  outcome: outcome,
  loggedAt: loggedAt ?? DateTime.now(),
  wasExpiring: wasExpiring,
);

ProviderContainer _container(AppDatabase db, {List<FoodLogEntry>? seed}) =>
    ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        if (seed != null) foodLogSeedProvider.overrideWithValue(seed),
      ],
    );

void main() {
  group('FoodLogNotifier', () {
    test('record persists to Drift and survives reload', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      final notifier = c.read(foodLogProvider.notifier);

      await notifier.record(_entry(id: 'fl1', outcome: FoodLogOutcome.wasted));
      expect(c.read(foodLogProvider).single.id, 'fl1');

      // reload reads from Drift, not memory -> proves the write hit disk.
      await notifier.reload();
      final reloaded = c.read(foodLogProvider).single;
      expect(reloaded.id, 'fl1');
      expect(reloaded.outcome, FoodLogOutcome.wasted);
    });

    test('record is append-only and ignores a blank id', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      final notifier = c.read(foodLogProvider.notifier);

      await notifier.record(_entry(id: 'a'));
      await notifier.record(_entry(id: '')); // ignored
      await notifier.record(_entry(id: 'b'));

      expect(c.read(foodLogProvider).map((e) => e.id), ['a', 'b']);
    });

    test('undoRecord reverses a recorded entry in state and on disk', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      final notifier = c.read(foodLogProvider.notifier);

      await notifier.record(_entry(id: 'keep'));
      await notifier.record(_entry(id: 'oops', outcome: FoodLogOutcome.wasted));
      await notifier.undoRecord('oops');

      expect(c.read(foodLogProvider).map((e) => e.id), ['keep']);
      // reload proves the targeted delete hit disk (not just state).
      await notifier.reload();
      expect(c.read(foodLogProvider).map((e) => e.id), ['keep']);
    });

    test('reload drops rows older than the recent window', () async {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = _container(db);
      addTearDown(c.dispose);
      final notifier = c.read(foodLogProvider.notifier);

      final old = DateTime.now().toUtc().subtract(
        foodLogRecentWindow + const Duration(days: 5),
      );
      await notifier.record(_entry(id: 'old', loggedAt: old));
      await notifier.record(_entry(id: 'recent'));

      await notifier.reload();
      expect(c.read(foodLogProvider).map((e) => e.id), ['recent']);
    });
  });

  group('computeFoodLogStats', () {
    test('counts consumed / wasted / rescued', () {
      final entries = [
        _entry(id: '1', outcome: FoodLogOutcome.consumed),
        _entry(id: '2', outcome: FoodLogOutcome.consumed, wasExpiring: true),
        _entry(id: '3', outcome: FoodLogOutcome.wasted),
        _entry(id: '4', outcome: FoodLogOutcome.wasted, wasExpiring: true),
      ];
      final stats = computeFoodLogStats(
        entries,
        since: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(stats.consumed, 2);
      expect(stats.wasted, 2);
      expect(stats.rescued, 1); // only the consumed+expiring one
      expect(stats.total, 4);
      expect(stats.wasteRate, 0.5);
    });

    test('excludes entries logged before the cutoff', () {
      final now = DateTime.now();
      final entries = [
        _entry(id: 'in', loggedAt: now),
        _entry(id: 'out', loggedAt: now.subtract(const Duration(days: 10))),
      ];
      final stats = computeFoodLogStats(
        entries,
        since: now.subtract(const Duration(days: 1)),
      );
      expect(stats.total, 1);
    });

    test('empty stats report a zero waste rate and isEmpty', () {
      final stats = computeFoodLogStats(const [], since: DateTime(2000));
      expect(stats.isEmpty, isTrue);
      expect(stats.wasteRate, 0);
      expect(stats.total, 0);
    });
  });

  group('derived providers', () {
    test('foodLogMonthStatsProvider aggregates this-month entries', () {
      final db = newTestDatabase();
      addTearDown(db.close);
      final old = DateTime.now().subtract(const Duration(days: 400));
      final c = _container(
        db,
        seed: [
          _entry(id: '1', outcome: FoodLogOutcome.consumed, wasExpiring: true),
          _entry(id: '2', outcome: FoodLogOutcome.wasted),
          _entry(id: 'old', outcome: FoodLogOutcome.wasted, loggedAt: old),
        ],
      );
      addTearDown(c.dispose);

      final stats = c.read(foodLogMonthStatsProvider);
      expect(stats.consumed, 1);
      expect(stats.wasted, 1); // the 400-day-old one is excluded
      expect(stats.rescued, 1);
    });

    test('foodLogWastedByCategoryProvider ranks wasted categories desc', () {
      final db = newTestDatabase();
      addTearDown(db.close);
      final c = _container(
        db,
        seed: [
          _entry(
            id: '1',
            outcome: FoodLogOutcome.wasted,
            category: FoodCategories.freshProduce,
          ),
          _entry(
            id: '2',
            outcome: FoodLogOutcome.wasted,
            category: FoodCategories.freshProduce,
          ),
          _entry(
            id: '3',
            outcome: FoodLogOutcome.wasted,
            category: FoodCategories.dairyAndEggs,
          ),
          // consumed items never count toward wasted-by-category.
          _entry(
            id: '4',
            outcome: FoodLogOutcome.consumed,
            category: FoodCategories.meatAndSeafood,
          ),
        ],
      );
      addTearDown(c.dispose);

      final ranked = c.read(foodLogWastedByCategoryProvider);
      expect(ranked, [
        (category: FoodCategories.freshProduce, count: 2),
        (category: FoodCategories.dairyAndEggs, count: 1),
      ]);
    });
  });

  group('windowed providers', () {
    test('foodLogWindowStatsProvider widens with the selected window', () {
      final db = newTestDatabase();
      addTearDown(db.close);
      // 40 days ago is always before this month's start (max month = 31 days)
      // yet within the 90-day window.
      final old = DateTime.now().subtract(const Duration(days: 40));
      final c = _container(
        db,
        seed: [
          _entry(id: 'recent'),
          _entry(id: 'old', loggedAt: old),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(foodLogWindowStatsProvider).total, 1); // 本月 default
      c.read(wasteStatsWindowProvider.notifier).state =
          WasteStatsWindow.last90Days;
      expect(c.read(foodLogWindowStatsProvider).total, 2);
    });

    test('foodLogWastedByCategoryForWindowProvider follows the window', () {
      final db = newTestDatabase();
      addTearDown(db.close);
      final old = DateTime.now().subtract(const Duration(days: 40));
      final c = _container(
        db,
        seed: [
          _entry(
            id: 'r',
            outcome: FoodLogOutcome.wasted,
            category: FoodCategories.freshProduce,
          ),
          _entry(
            id: 'o',
            outcome: FoodLogOutcome.wasted,
            category: FoodCategories.dairyAndEggs,
            loggedAt: old,
          ),
        ],
      );
      addTearDown(c.dispose);

      expect(c.read(foodLogWastedByCategoryForWindowProvider), [
        (category: FoodCategories.freshProduce, count: 1),
      ]);
      c.read(wasteStatsWindowProvider.notifier).state =
          WasteStatsWindow.last90Days;
      expect(c.read(foodLogWastedByCategoryForWindowProvider).length, 2);
    });
  });
}
