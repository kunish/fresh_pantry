import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/widgets/dashboard/household_chip.dart';
import 'helpers/household_gateway_stub.dart';

Future<HouseholdSessionController> _seeded({List<HouseholdInvitePreview> invites = const []}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(id: 'h1', name: '我家', ownerId: 'owner_1', defaultStorageArea: 'fridge'),
    ],
    pendingInvites: invites,
  );
  final controller = HouseholdSessionController(stub);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  await controller.refreshPendingInvites();
  return controller;
}

void main() {
  testWidgets('chip shows current household name', (tester) async {
    final controller = await _seeded();
    await tester.pumpWidget(ProviderScope(
      overrides: [householdSessionControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: Scaffold(body: HouseholdChip())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('我家'), findsOneWidget);
    expect(find.byKey(const ValueKey('household_chip_badge')), findsNothing);
  });

  testWidgets('chip shows badge when there is an incoming invite', (tester) async {
    final controller = await _seeded(invites: const [
      HouseholdInvitePreview(
        inviteId: 'inv1', householdId: 'h9', householdName: '李家',
        ownerEmail: 'o@ex.com', invitedEmail: 'me@ex.com',
        memberCount: 1, inventoryCount: 0, shoppingCount: 0, customRecipeCount: 0,
      ),
    ]);
    await tester.pumpWidget(ProviderScope(
      overrides: [householdSessionControllerProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: Scaffold(body: HouseholdChip())),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('household_chip_badge')), findsOneWidget);
  });
}
