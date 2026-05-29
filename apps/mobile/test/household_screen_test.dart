import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/screens/household_screen.dart';
import 'helpers/household_gateway_stub.dart';

// ---------------------------------------------------------------------------
// Shared harness: owner household seeded as 'h1' / 'owner_1'
// ---------------------------------------------------------------------------
Future<(HouseholdGatewayStub, HouseholdSessionController)>
    _buildOwnerController({
  Object? dissolveError,
}) async {
  final stub = HouseholdGatewayStub(
    isAuthenticated: true,
    households: const [
      Household(
        id: 'h1',
        name: 'Kunish Kitchen',
        ownerId: 'owner_1',
        defaultStorageArea: 'fridge',
      ),
    ],
    members: const [
      HouseholdMember(
        householdId: 'h1',
        userId: 'owner_1',
        role: 'owner',
        email: 'owner@example.com',
      ),
    ],
  )..dissolveHouseholdError = dissolveError;

  final controller = HouseholdSessionController(stub);
  await controller.refreshHouseholds();
  await controller.switchHousehold('h1');
  return (stub, controller);
}

Widget _wrap(HouseholdSessionController controller) => ProviderScope(
      overrides: [
        householdSessionControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: HouseholdScreen()),
    );

void main() {
  testWidgets('HouseholdScreen renders current household and members',
      (tester) async {
    final stub = HouseholdGatewayStub(
      isAuthenticated: true,
      households: const [
        Household(
            id: 'h1',
            name: '我家',
            ownerId: 'owner_1',
            defaultStorageArea: 'fridge'),
      ],
      members: const [
        HouseholdMember(
            householdId: 'h1',
            userId: 'owner_1',
            role: 'owner',
            email: 'me@ex.com'),
      ],
    );
    final controller = HouseholdSessionController(stub);
    await controller.refreshHouseholds();
    await controller.switchHousehold('h1');

    await tester.pumpWidget(ProviderScope(
      overrides: [
        householdSessionControllerProvider.overrideWith((ref) => controller),
      ],
      child: const MaterialApp(home: HouseholdScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('我家'), findsOneWidget);
    expect(find.text('me@ex.com'), findsOneWidget);
  });

  // ── wiring tests (relocated from household_invite_widget_test.dart) ───────

  testWidgets(
      'HouseholdScreen creates open invite link for current household',
      (tester) async {
    final (stub, controller) = await _buildOwnerController();

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('扫码/链接邀请'));
    await tester.pumpAndSettle();

    expect(stub.inviteHouseholdId, 'h1');
    expect(stub.inviteEmail, isEmpty);
    expect(find.text('邀请链接已创建'), findsOneWidget);
    expect(find.text('分享链接或二维码，家人登录后即可加入'), findsOneWidget);
    expect(find.text('分享二维码'), findsOneWidget);
  });

  testWidgets(
      'HouseholdScreen creates email invite for current household and trims address',
      (tester) async {
    final (stub, controller) = await _buildOwnerController();

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('邮箱定向邀请'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, '成员邮箱'),
      ' member@example.com ',
    );
    await tester.tap(find.text('发送邀请'));
    await tester.pumpAndSettle();

    expect(stub.inviteHouseholdId, 'h1');
    expect(stub.inviteEmail, 'member@example.com');
    expect(find.text('邀请链接已创建'), findsOneWidget);
    expect(find.text('member@example.com'), findsOneWidget);
    expect(find.text('复制链接'), findsOneWidget);
  });

  testWidgets('HouseholdScreen lets owner confirm household dissolution',
      (tester) async {
    final (stub, controller) = await _buildOwnerController();

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '解散家庭'));
    await tester.pumpAndSettle();

    expect(
      find.text('确定解散「Kunish Kitchen」？这会删除家庭、成员、邀请以及所有共享食材、采购和菜谱数据，无法撤销。'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, '解散'));
    await tester.pumpAndSettle();

    expect(stub.dissolvedHouseholdId, 'h1');
    expect(find.text('已解散「Kunish Kitchen」'), findsOneWidget);
  });

  testWidgets('HouseholdScreen shows an error when dissolution fails',
      (tester) async {
    final (stub, controller) = await _buildOwnerController(
      dissolveError: StateError('boom'),
    );

    await tester.pumpWidget(_wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '解散家庭'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '解散'));
    await tester.pumpAndSettle();

    expect(stub.dissolvedHouseholdId, isEmpty);
    expect(find.textContaining('boom'), findsOneWidget);
    expect(find.text('Kunish Kitchen'), findsWidgets);
  });
}
