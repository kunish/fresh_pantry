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
}
