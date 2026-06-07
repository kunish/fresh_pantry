import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/models/sync_metadata.dart';

FoodLogEntry _entry({
  String id = 'fl-1',
  String name = '番茄',
  String category = FoodCategories.freshProduce,
  FoodLogOutcome outcome = FoodLogOutcome.consumed,
  DateTime? loggedAt,
  bool wasExpiring = false,
}) => FoodLogEntry(
  id: id,
  name: name,
  category: category,
  outcome: outcome,
  loggedAt: loggedAt ?? DateTime.utc(2026, 6, 7, 12),
  wasExpiring: wasExpiring,
);

void main() {
  group('FoodLogEntry construction', () {
    test('loggedAt is normalized to UTC', () {
      final local = DateTime(2026, 6, 7, 8); // local time
      final entry = _entry(loggedAt: local);
      expect(entry.loggedAt.isUtc, isTrue);
      expect(entry.loggedAt, local.toUtc());
    });

    test('category defaults to other when omitted', () {
      final entry = FoodLogEntry(
        id: 'x',
        name: '某物',
        outcome: FoodLogOutcome.wasted,
        loggedAt: DateTime.utc(2026, 6, 7),
      );
      expect(entry.category, FoodCategories.other);
    });

    test('outcome helpers', () {
      expect(_entry(outcome: FoodLogOutcome.consumed).isConsumed, isTrue);
      expect(_entry(outcome: FoodLogOutcome.wasted).isWasted, isTrue);
    });

    test('rescuedExpiring only when consumed AND was expiring', () {
      final rescued =
          _entry(outcome: FoodLogOutcome.consumed, wasExpiring: true);
      final freshConsumed =
          _entry(outcome: FoodLogOutcome.consumed, wasExpiring: false);
      final wastedExpiring =
          _entry(outcome: FoodLogOutcome.wasted, wasExpiring: true);
      expect(rescued.rescuedExpiring, isTrue);
      expect(freshConsumed.rescuedExpiring, isFalse);
      expect(wastedExpiring.rescuedExpiring, isFalse);
    });
  });

  group('FoodLogOutcome.fromName', () {
    test('parses known names', () {
      expect(FoodLogOutcome.fromName('consumed'), FoodLogOutcome.consumed);
      expect(FoodLogOutcome.fromName('wasted'), FoodLogOutcome.wasted);
    });

    test('falls back to consumed on unknown/null (never overstate waste)', () {
      expect(FoodLogOutcome.fromName('garbage'), FoodLogOutcome.consumed);
      expect(FoodLogOutcome.fromName(null), FoodLogOutcome.consumed);
    });
  });

  group('FoodLogEntry.fromJson', () {
    test('round-trip preserves all fields', () {
      final original = _entry(
        id: 'fl-9',
        name: '鸡蛋',
        category: FoodCategories.dairyAndEggs,
        outcome: FoodLogOutcome.wasted,
        loggedAt: DateTime.utc(2026, 6, 6, 9, 30),
        wasExpiring: true,
      );
      final restored = FoodLogEntry.fromJson(original.toJson());

      expect(restored.id, original.id);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.outcome, original.outcome);
      expect(restored.loggedAt, original.loggedAt);
      expect(restored.wasExpiring, original.wasExpiring);
    });

    test('uses defaults for missing optional fields', () {
      final entry = FoodLogEntry.fromJson({
        'id': 'fl-2',
        'loggedAt': DateTime.utc(2026, 6, 7).toIso8601String(),
      });
      expect(entry.name, '');
      expect(entry.category, FoodCategories.other);
      expect(entry.outcome, FoodLogOutcome.consumed);
      expect(entry.wasExpiring, isFalse);
    });

    test('throws on missing loggedAt so the repo can skip malformed row', () {
      expect(
        () => FoodLogEntry.fromJson({'id': 'fl-3', 'outcome': 'wasted'}),
        throwsFormatException,
      );
    });

    test('throws on unparseable loggedAt', () {
      expect(
        () => FoodLogEntry.fromJson({'id': 'fl-4', 'loggedAt': 'not-a-date'}),
        throwsFormatException,
      );
    });

    test('preserves remote sync metadata', () {
      final entry = FoodLogEntry(
        id: 'fl-5',
        name: '牛奶',
        outcome: FoodLogOutcome.consumed,
        loggedAt: DateTime.utc(2026, 6, 1),
        remoteVersion: 5,
        clientUpdatedAt: DateTime.utc(2026, 5, 27),
        deletedAt: DateTime.utc(2026, 5, 28),
      );
      final decoded = FoodLogEntry.fromJson(entry.toJson());

      expect(decoded.remoteVersion, 5);
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

  group('FoodLogEntry.copyWith', () {
    test('overrides selected fields and keeps the rest', () {
      final updated = _entry().copyWith(outcome: FoodLogOutcome.wasted);
      expect(updated.outcome, FoodLogOutcome.wasted);
      expect(updated.name, '番茄');
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
