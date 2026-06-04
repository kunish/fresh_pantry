import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:fresh_pantry/storage/inventory_repo.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

void main() {
  testWidgets('debug settings include Sentry verification action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(database: db),
          notificationServiceProvider.overrideWithValue(NotificationService()),
          householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('sentry_verify_action')),
      200,
    );

    expect(find.byKey(const Key('sentry_verify_action')), findsOneWidget);
    expect(find.text('验证 Sentry'), findsOneWidget);
  });

  testWidgets('tap 导出到剪贴板 copies a v2 JSON envelope to clipboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    String? capturedClipboard;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            capturedClipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: const [
              Ingredient(
                name: '苹果',
                quantity: '3',
                unit: '个',
                imageUrl: '',
                freshnessPercent: 1.0,
                state: FreshnessState.fresh,
              ),
            ],
          ),
          notificationServiceProvider.overrideWithValue(NotificationService()),
          householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('backup_export_action')),
      200,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup_export_action')));
    await tester.pumpAndSettle();

    expect(capturedClipboard, isNotNull);
    expect(capturedClipboard, contains('"version": 2'));
    expect(capturedClipboard, contains('"inventory"'));
    expect(capturedClipboard, contains('苹果'));
  });

  testWidgets('tap 从剪贴板导入 → confirm restores into Drift and prompts restart', (
    tester,
  ) async {
    const blob = '''
{
  "version": 2,
  "exportedAt": "2026-05-15T13:00:00.000Z",
  "data": {
    "inventory": [
      {"name": "导入测试", "quantity": "1", "unit": "个"}
    ]
  }
}
''';
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final db = newTestDatabase();
    addTearDown(db.close);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.getData') {
            return <String, dynamic>{'text': blob};
          }
          return null;
        });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...testStorageOverrides(
            database: db,
            inventory: const [
              Ingredient(
                name: '旧',
                quantity: '1',
                unit: '个',
                imageUrl: '',
                freshnessPercent: 1.0,
                state: FreshnessState.fresh,
              ),
            ],
          ),
          notificationServiceProvider.overrideWithValue(NotificationService()),
          householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.byKey(const Key('backup_import_action')),
      200,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('backup_import_action')));
    await tester.pumpAndSettle();

    expect(
      find.text('确认导入?'),
      findsOneWidget,
      reason: 'confirm dialog must appear before destructive write',
    );

    await tester.tap(find.text('确认覆盖'));
    await tester.pumpAndSettle();

    expect(find.textContaining('请重启 App'), findsOneWidget);

    // The restore went through the live Drift store (the real source of truth),
    // not orphaned SharedPreferences blobs: the local-only ('') scope now holds
    // the imported item and not the seeded one.
    final restored = await InventoryRepo(db).loadAllFor('');
    expect(restored.map((i) => i.name), contains('导入测试'));
    expect(restored.map((i) => i.name), isNot(contains('旧')));
  });
}
