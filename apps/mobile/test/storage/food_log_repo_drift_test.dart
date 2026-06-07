import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/food_log_repo.dart';

FoodLogEntry _entry(
  String id, {
  FoodLogOutcome outcome = FoodLogOutcome.consumed,
  DateTime? loggedAt,
  String name = '番茄',
  bool wasExpiring = false,
}) => FoodLogEntry(
  id: id,
  name: name,
  category: FoodCategories.freshProduce,
  outcome: outcome,
  loggedAt: loggedAt ?? DateTime.utc(2026, 6, 7, 12),
  wasExpiring: wasExpiring,
);

void main() {
  late AppDatabase db;
  late FoodLogRepo repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = FoodLogRepo(db);
  });

  tearDown(() => db.close());

  test('append then loadAllFor round-trips and skips blank id', () async {
    await repo.append('hh-1', _entry('fl1', outcome: FoodLogOutcome.wasted));
    await repo.append('hh-1', _entry('', outcome: FoodLogOutcome.consumed));

    final loaded = await repo.loadAllFor('hh-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'fl1');
    expect(loaded.first.outcome, FoodLogOutcome.wasted);
  });

  test('loadAllFor only returns the requested household scope', () async {
    await repo.append('hh-1', _entry('a'));
    await repo.append('hh-2', _entry('b'));

    expect((await repo.loadAllFor('hh-1')).map((e) => e.id), ['a']);
    expect((await repo.loadAllFor('hh-2')).map((e) => e.id), ['b']);
  });

  test('loadRecentFor returns only rows at/after the cutoff', () async {
    final old = DateTime.utc(2026, 5, 1, 12);
    final recent = DateTime.utc(2026, 6, 6, 12);
    await repo.append('hh-1', _entry('old', loggedAt: old));
    await repo.append('hh-1', _entry('recent', loggedAt: recent));

    final cutoff = DateTime.utc(2026, 6, 1).millisecondsSinceEpoch;
    final loaded = await repo.loadRecentFor('hh-1', sinceMs: cutoff);
    expect(loaded.map((e) => e.id), ['recent']);
  });

  test('append is idempotent on the same id (insertOrReplace)', () async {
    await repo.append('hh-1', _entry('dup', outcome: FoodLogOutcome.consumed));
    await repo.append('hh-1', _entry('dup', outcome: FoodLogOutcome.wasted));

    final loaded = await repo.loadAllFor('hh-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.outcome, FoodLogOutcome.wasted);
  });

  test('saveEntries replaces the prior snapshot for that scope', () async {
    await repo.saveEntries('hh-1', [_entry('a'), _entry('b')]);
    await repo.saveEntries('hh-1', [_entry('a')]);

    expect((await repo.loadAllFor('hh-1')).map((e) => e.id), ['a']);
  });

  test('deleteHouseholdScope clears only that scope', () async {
    await repo.append('hh-1', _entry('a'));
    await repo.append('hh-2', _entry('b'));

    await repo.deleteHouseholdScope('hh-1');

    expect(await repo.loadAllFor('hh-1'), isEmpty);
    expect((await repo.loadAllFor('hh-2')).map((e) => e.id), ['b']);
  });

  test('hydrate seed is returned once then cleared', () {
    repo.hydrate([_entry('seed')]);
    expect(repo.loadAll().map((e) => e.id), ['seed']);
    expect(repo.loadAll(), isEmpty); // one-shot
  });

  test('round-trips the full field set including wasExpiring/category', () async {
    final original = _entry(
      'fl9',
      outcome: FoodLogOutcome.consumed,
      loggedAt: DateTime.utc(2026, 6, 5, 9, 30),
      name: '酸奶',
      wasExpiring: true,
    );
    await repo.append('hh-1', original);

    final loaded = (await repo.loadAllFor('hh-1')).single;
    expect(loaded.name, '酸奶');
    expect(loaded.category, FoodCategories.freshProduce);
    expect(loaded.wasExpiring, isTrue);
    expect(loaded.rescuedExpiring, isTrue);
    expect(loaded.loggedAt, DateTime.utc(2026, 6, 5, 9, 30));
  });
}
