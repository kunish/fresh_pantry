import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/notification_service_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/settings_screen.dart';
import 'package:fresh_pantry/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/household_gateway_stub.dart';
import 'support/test_database.dart';

Future<HouseholdSessionController> _seeded({
  List<HouseholdInvitePreview> invites = const [],
}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(
        id: 'h1',
        name: '我家',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ],
    pendingInvites: invites,
  );
  final controller = HouseholdSessionController(stub);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  await controller.refreshPendingInvites();
  return controller;
}

Future<void> _pumpSettings(
  WidgetTester tester,
  HouseholdSessionController controller,
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
        householdSessionControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

const _sampleInvite = HouseholdInvitePreview(
  inviteId: 'inv1',
  householdId: 'h9',
  householdName: '李家',
  ownerEmail: 'o@ex.com',
  invitedEmail: 'me@ex.com',
  memberCount: 1,
  inventoryCount: 0,
  shoppingCount: 0,
  customRecipeCount: 0,
);

void main() {
  testWidgets('household row shows invite badge with pending invites',
      (tester) async {
    final controller = await _seeded(invites: const [_sampleInvite]);
    await _pumpSettings(tester, controller);

    expect(
      find.byKey(const ValueKey('household_row_invite_badge')),
      findsOneWidget,
    );
  });

  testWidgets('household row has no badge without pending invites',
      (tester) async {
    final controller = await _seeded();
    await _pumpSettings(tester, controller);

    expect(
      find.byKey(const ValueKey('household_row_invite_badge')),
      findsNothing,
    );
  });
}
