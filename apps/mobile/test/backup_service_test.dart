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

  group('BackupService.importFromMap', () {
    test('writes each present user-data key back to prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'exportedAt': '2026-05-15T13:00:00.000Z',
        'data': {
          'inventory_items': '[{"name":"苹果"}]',
          'shopping_items': '[]',
        },
      });

      expect(prefs.getString('inventory_items'), '[{"name":"苹果"}]');
      expect(prefs.getString('shopping_items'), '[]');
      expect(prefs.getString('add_history'), isNull);
    });

    test('ignores keys outside the userDataKeys allowlist', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'data': {
          'inventory_items': '[]',
          'food_details_cache': '"malicious"',
          'unknown_key': '"hostile"',
        },
      });

      expect(prefs.getString('inventory_items'), '[]');
      expect(prefs.getString('food_details_cache'), isNull,
          reason: 'cache keys must not be importable');
      expect(prefs.getString('unknown_key'), isNull);
    });

    test('overwrites existing values', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"old":true}]',
      });
      final prefs = await SharedPreferences.getInstance();

      await BackupService.importFromMap(prefs, {
        'version': 1,
        'data': {'inventory_items': '[{"new":true}]'},
      });

      expect(prefs.getString('inventory_items'), '[{"new":true}]');
    });

    test('round-trips: export → encode → decode → import → same prefs', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"葱"}]',
        'shopping_items': '[{"id":"si_1"}]',
        'add_history': '{"葱":{"count":3}}',
      });
      final source = await SharedPreferences.getInstance();
      final exported = BackupService.exportToMap(source);
      final json = BackupService.encodeToJson(exported);

      SharedPreferences.setMockInitialValues({});
      final target = await SharedPreferences.getInstance();
      final decoded = BackupService.decodeFromJson(json);
      await BackupService.importFromMap(target, decoded);

      expect(target.getString('inventory_items'), '[{"name":"葱"}]');
      expect(target.getString('shopping_items'), '[{"id":"si_1"}]');
      expect(target.getString('add_history'), '{"葱":{"count":3}}');
    });

    test(
      'atomic: a corrupted inner payload throws and writes NOTHING',
      () async {
        SharedPreferences.setMockInitialValues({
          'inventory_items': '[{"name":"现有食材"}]',
          'shopping_items': '[{"id":"si_keep"}]',
        });
        final prefs = await SharedPreferences.getInstance();

        // shopping_items is a valid list but inventory_items is truncated
        // (no longer decodes to a JSON list).
        expect(
          () => BackupService.importFromMap(prefs, {
            'version': 1,
            'data': {
              'shopping_items': '[{"id":"si_new"}]',
              'inventory_items': '[{"name":"苹果"', // truncated
            },
          }),
          throwsA(isA<FormatException>()),
        );

        // Nothing was written: existing good data is fully intact.
        expect(prefs.getString('inventory_items'), '[{"name":"现有食材"}]');
        expect(prefs.getString('shopping_items'), '[{"id":"si_keep"}]');
      },
    );

    test('atomic: a list payload that decodes to a non-list throws', () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[{"name":"现有食材"}]',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => BackupService.importFromMap(prefs, {
          'version': 1,
          'data': {'inventory_items': '{"not":"a list"}'},
        }),
        throwsA(isA<FormatException>()),
      );

      expect(prefs.getString('inventory_items'), '[{"name":"现有食材"}]');
    });

    test('atomic: a map payload that decodes to a non-map throws', () async {
      SharedPreferences.setMockInitialValues({
        'add_history': '{"葱":{"count":3}}',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => BackupService.importFromMap(prefs, {
          'version': 1,
          'data': {'add_history': '[1,2,3]'},
        }),
        throwsA(isA<FormatException>()),
      );

      expect(prefs.getString('add_history'), '{"葱":{"count":3}}');
    });

    test('atomic: a non-string payload throws and writes nothing', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(
        () => BackupService.importFromMap(prefs, {
          'version': 1,
          'data': {'shopping_items': 42},
        }),
        throwsA(isA<FormatException>()),
      );

      expect(prefs.getString('shopping_items'), isNull);
    });

    test('onImported runs only after a successful import', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var imported = 0;

      await BackupService.importFromMap(
        prefs,
        {
          'version': 1,
          'data': {'shopping_items': '[]'},
        },
        onImported: () async => imported++,
      );

      expect(imported, 1);
      expect(prefs.getString('shopping_items'), '[]');
    });

    test('onImported does NOT run when the import throws', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var imported = 0;

      await expectLater(
        BackupService.importFromMap(
          prefs,
          {
            'version': 1,
            'data': {'inventory_items': '[truncated'},
          },
          onImported: () async => imported++,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(imported, 0);
      expect(prefs.getString('inventory_items'), isNull);
    });
  });
}
