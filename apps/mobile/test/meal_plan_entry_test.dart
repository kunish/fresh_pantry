import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/meal_plan_entry.dart';
import 'package:fresh_pantry/models/sync_metadata.dart';

MealPlanEntry _entry({
  String id = 'mp-1',
  DateTime? date,
  String recipeId = 'r1',
  String recipeName = '番茄炒蛋',
}) => MealPlanEntry(
  id: id,
  date: date ?? DateTime(2026, 6, 8),
  recipeId: recipeId,
  recipeName: recipeName,
  recipeImageUrl: 'https://example.com/x.jpg',
  servings: 2,
  done: true,
);

void main() {
  group('MealPlanEntry date normalization', () {
    test('constructor truncates time-of-day to local midnight', () {
      final entry = _entry(date: DateTime(2026, 6, 8, 23, 59, 59));
      expect(entry.date, DateTime(2026, 6, 8));
    });

    test('dateKey is a stable yyyy-MM-dd string regardless of time', () {
      expect(MealPlanEntry.dateKey(DateTime(2026, 6, 8, 14, 30)), '2026-06-08');
      expect(MealPlanEntry.dateKey(DateTime(2026, 1, 3)), '2026-01-03');
    });

    test('dateOnly drops the time component', () {
      expect(
        MealPlanEntry.dateOnly(DateTime(2026, 12, 31, 8, 0)),
        DateTime(2026, 12, 31),
      );
    });
  });

  group('MealPlanEntry.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = _entry(
        id: '11111111-1111-1111-1111-111111111111',
        date: DateTime(2026, 6, 8),
      );
      final restored = MealPlanEntry.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.date, original.date);
      expect(restored.recipeId, original.recipeId);
      expect(restored.recipeName, original.recipeName);
      expect(restored.recipeImageUrl, original.recipeImageUrl);
      expect(restored.servings, original.servings);
      expect(restored.done, original.done);
    });

    test('uses defaults for missing optional fields', () {
      final entry = MealPlanEntry.fromJson({
        'id': 'mp-2',
        'date': '2026-06-08',
        'recipeId': 'r9',
      });
      expect(entry.recipeName, '');
      expect(entry.recipeImageUrl, isNull);
      expect(entry.servings, 1);
      expect(entry.done, isFalse);
    });

    test('tolerates a full ISO date string and normalizes to date-only', () {
      final entry = MealPlanEntry.fromJson({
        'id': 'mp-3',
        'date': '2026-06-08T14:30:00.000',
        'recipeId': 'r1',
      });
      expect(entry.date, DateTime(2026, 6, 8));
    });

    test('throws on missing date so the repo can skip the malformed row', () {
      expect(
        () => MealPlanEntry.fromJson({'id': 'mp-4', 'recipeId': 'r1'}),
        throwsFormatException,
      );
    });

    test('throws on unparseable date', () {
      expect(
        () => MealPlanEntry.fromJson({
          'id': 'mp-5',
          'date': 'not-a-date',
          'recipeId': 'r1',
        }),
        throwsFormatException,
      );
    });

    test('preserves remote sync metadata', () {
      final entry = MealPlanEntry(
        id: '22222222-2222-2222-2222-222222222222',
        date: DateTime(2026, 6, 8),
        recipeId: 'r1',
        recipeName: 'Soup',
        remoteVersion: 5,
        clientUpdatedAt: DateTime.utc(2026, 5, 27),
        deletedAt: DateTime.utc(2026, 5, 28),
      );
      final decoded = MealPlanEntry.fromJson(entry.toJson());

      expect(decoded.remoteVersion, 5);
      expect(decoded.clientUpdatedAt, DateTime.utc(2026, 5, 27));
      expect(decoded.deletedAt, DateTime.utc(2026, 5, 28));
      expect(
        decoded.syncMetadata,
        SyncMetadata(
          remoteVersion: 5,
          clientUpdatedAt: DateTime.utc(2026, 5, 27),
          deletedAt: DateTime.utc(2026, 5, 28),
        ),
      );
    });
  });

  group('MealPlanEntry.copyWith', () {
    test('overrides selected fields and keeps the rest', () {
      final updated = _entry().copyWith(done: false, servings: 4);
      expect(updated.done, isFalse);
      expect(updated.servings, 4);
      expect(updated.recipeName, '番茄炒蛋');
    });

    test('can clear nullable sync timestamps', () {
      final entry = _entry().copyWith(
        clientUpdatedAt: DateTime.utc(2026, 5, 27),
        deletedAt: DateTime.utc(2026, 5, 28),
      );
      final cleared = entry.copyWith(
        clearClientUpdatedAt: true,
        clearDeletedAt: true,
      );
      expect(cleared.clientUpdatedAt, isNull);
      expect(cleared.deletedAt, isNull);
    });

    test('identity is id-based', () {
      expect(_entry(id: 'a'), _entry(id: 'a'));
      expect(_entry(id: 'a'), isNot(_entry(id: 'b')));
    });
  });
}
