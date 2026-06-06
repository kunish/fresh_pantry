import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/providers/navigation_provider.dart';
import 'package:fresh_pantry/widgets/common/top_app_bar.dart';

import 'helpers/household_gateway_stub.dart';

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
  testWidgets('search button activates the search overlay provider', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        householdGatewayProvider.overrideWithValue(HouseholdGatewayStub()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(body: TopAppBar()),
        ),
      ),
    );

    await tester.tap(find.byTooltip('搜索'));
    await tester.pump();

    expect(container.read(searchActiveProvider), isTrue);
  });

  testWidgets('settings gear shows invite badge when there is a pending invite',
      (tester) async {
    final controller = await _seeded(invites: const [_sampleInvite]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdSessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: Scaffold(body: TopAppBar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_invite_badge')),
      findsOneWidget,
    );
    expect(find.byTooltip('设置(有待处理邀请)'), findsOneWidget);
  });

  testWidgets('settings gear has no badge without pending invites',
      (tester) async {
    final controller = await _seeded();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdSessionControllerProvider.overrideWith((ref) => controller),
        ],
        child: const MaterialApp(home: Scaffold(body: TopAppBar())),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_invite_badge')),
      findsNothing,
    );
    expect(find.byTooltip('设置'), findsOneWidget);
  });
}
