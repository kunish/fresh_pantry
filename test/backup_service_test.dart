import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/backup_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BackupService.exportToMap', () {
    test('returns version 1 + exportedAt ISO8601 + data object', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"苹果"}]',
        'shopping_items': '[]',
      });
      final prefs = await SharedPreferences.getInstance();

      final map = BackupService.exportToMap(prefs);

      expect(map['version'], 1);
      expect(map['exportedAt'], isA<String>());
      expect(DateTime.tryParse(map['exportedAt'] as String), isNotNull);
      expect(map['data'], isA<Map<String, dynamic>>());
    });

    test('includes only present user-data keys in data', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"苹果"}]',
        'shopping_items': '[]',
        // 'add_history' absent
        'food_details_cache': '{"should":"be skipped"}',
      });
      final prefs = await SharedPreferences.getInstance();

      final map = BackupService.exportToMap(prefs);
      final data = map['data'] as Map<String, dynamic>;

      expect(data['inventory_items'], '[{"name":"苹果"}]');
      expect(data['shopping_items'], '[]');
      expect(data.containsKey('add_history'), isFalse);
      expect(data.containsKey('food_details_cache'), isFalse,
          reason: 'cache keys must not be backed up');
    });
  });

  group('BackupService.encodeToJson / decodeFromJson', () {
    test('round-trips a map back to the same shape', () {
      final original = {
        'version': 1,
        'exportedAt': '2026-05-15T13:00:00.000Z',
        'data': {
          'inventory_items': '[{"name":"苹果"}]',
        },
      };

      final json = BackupService.encodeToJson(original);
      final decoded = BackupService.decodeFromJson(json);

      expect(decoded, original);
    });

    test('encodeToJson produces pretty-printed (indent 2) output', () {
      final json = BackupService.encodeToJson({'version': 1, 'data': {}});
      expect(json, contains('\n  '));
    });

    test('decodeFromJson throws on malformed JSON', () {
      expect(
        () => BackupService.decodeFromJson('{not valid'),
        throwsA(isA<FormatException>()),
      );
    });

    test('decodeFromJson throws on unsupported version', () {
      final json = BackupService.encodeToJson({'version': 99, 'data': {}});
      expect(
        () => BackupService.decodeFromJson(json),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('decodeFromJson throws when version is missing', () {
      expect(
        () => BackupService.decodeFromJson('{"data":{}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });

    test('decodeFromJson throws BackupVersionException for float version', () {
      expect(
        () => BackupService.decodeFromJson('{"version": 1.0, "data": {}}'),
        throwsA(isA<BackupVersionException>()),
      );
    });
  });
}
