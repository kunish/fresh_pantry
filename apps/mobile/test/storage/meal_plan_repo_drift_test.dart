import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/storage/drift/app_database.dart';
import 'package:fresh_pantry/storage/meal_plan_repo.dart';

MealPlanEntry _entry(
  String id,
  String recipeId, {
  DateTime? date,
  String name = 'Soup',
}) => MealPlanEntry(
  id: id,
  date: date ?? DateTime(2026, 6, 8),
  recipeId: recipeId,
  recipeName: name,
);

void main() {
  late AppDatabase db;
  late MealPlanRepo repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = MealPlanRepo(db);
  });

  tearDown(() => db.close());

  test('saveEntries then loadAllFor round-trips and skips blank id/recipeId', () async {
    await repo.saveEntries('hh-1', [
      _entry('mp1', 'r1'),
      _entry('', 'r2'), // blank id -> skipped
      _entry('mp3', ''), // blank recipeId -> skipped
    ]);

    final loaded = await repo.loadAllFor('hh-1');
    expect(loaded, hasLength(1));
    expect(loaded.first.id, 'mp1');
    expect(loaded.first.recipeId, 'r1');
    expect(loaded.first.date, DateTime(2026, 6, 8));
  });

  test('loadAllFor only returns the requested household scope', () async {
    await repo.saveEntries('hh-1', [_entry('a', 'r1')]);
    await repo.saveEntries('hh-2', [_entry('b', 'r2')]);

    expect((await repo.loadAllFor('hh-1')).map((e) => e.id), ['a']);
    expect((await repo.loadAllFor('hh-2')).map((e) => e.id), ['b']);
  });

  test('saveEntries replaces the prior snapshot for that scope', () async {
    await repo.saveEntries('hh-1', [_entry('a', 'r1'), _entry('b', 'r2')]);
    await repo.saveEntries('hh-1', [_entry('a', 'r1')]);

    expect((await repo.loadAllFor('hh-1')).map((e) => e.id), ['a']);
  });

  test('deleteHouseholdScope clears only that scope', () async {
    await repo.saveEntries('hh-1', [_entry('a', 'r1')]);
    await repo.saveEntries('hh-2', [_entry('b', 'r2')]);

    await repo.deleteHouseholdScope('hh-1');

    expect(await repo.loadAllFor('hh-1'), isEmpty);
    expect((await repo.loadAllFor('hh-2')).map((e) => e.id), ['b']);
  });

  test('hydrate seed is returned once then cleared', () {
    repo.hydrate([_entry('seed', 'r1')]);
    expect(repo.loadAll().map((e) => e.id), ['seed']);
    expect(repo.loadAll(), isEmpty); // one-shot
  });

  test('round-trips full field set including done/servings/image', () async {
    final original = MealPlanEntry(
      id: 'mp9',
      date: DateTime(2026, 6, 10),
      recipeId: 'r9',
      recipeName: '红烧肉',
      recipeImageUrl: 'https://example.com/x.jpg',
      servings: 3,
      done: true,
    );
    await repo.saveEntries('hh-1', [original]);

    final loaded = (await repo.loadAllFor('hh-1')).single;
    expect(loaded.recipeName, '红烧肉');
    expect(loaded.recipeImageUrl, 'https://example.com/x.jpg');
    expect(loaded.servings, 3);
    expect(loaded.done, isTrue);
    expect(loaded.date, DateTime(2026, 6, 10));
  });
}
