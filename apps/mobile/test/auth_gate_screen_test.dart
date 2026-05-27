import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';
import 'package:fresh_pantry/screens/auth_gate_screen.dart';
import 'package:fresh_pantry/sync/sync_providers.dart';

class FakeHouseholdGateway implements HouseholdGateway {
  FakeHouseholdGateway({
    this.initialHouseholds = const [],
    this.isAuthenticated = false,
    this.loadHouseholdsCompleter,
  });

  final authStateController = StreamController<void>.broadcast();
  List<Household> initialHouseholds;
  Completer<List<Household>>? loadHouseholdsCompleter;
  @override
  bool isAuthenticated;
  var sentEmail = '';
  var createdHouseholdName = '';

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {
    sentEmail = email;
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    return loadHouseholdsCompleter?.future ?? initialHouseholds;
  }

  @override
  Future<Household> createHousehold(String name) async {
    createdHouseholdName = name;
    final household = Household(
      id: 'household_1',
      name: name,
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    );
    initialHouseholds = [household];
    return household;
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  @override
  Future<String> createInvite({
    required String householdId,
    required String email,
  }) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> acceptInvite(String token) {
    throw UnimplementedError('Not needed by these tests.');
  }

  void emitAuthStateChange() {
    authStateController.add(null);
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('resolveSupabaseAuthRedirectUrl uses the mobile deep link', () {
    expect(
      resolveSupabaseAuthRedirectUrl(isWeb: false),
      'com.kunish.freshpantry://signin-callback/',
    );
  });

  test('resolveSupabaseAuthRedirectUrl uses the current web origin', () {
    expect(
      resolveSupabaseAuthRedirectUrl(
        isWeb: true,
        webBaseUri: Uri.parse('http://localhost:61733/#/login?x=1'),
      ),
      'http://localhost:61733/',
    );
  });

  testWidgets(
    'AuthGateScreen renders email OTP form when no household is loaded',
    (tester) async {
      await tester.pumpWidget(_wrap(FakeHouseholdGateway()));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '发送登录链接'), findsOneWidget);
      expect(find.text('App Shell'), findsNothing);
    },
  );

  testWidgets('AuthGateScreen sends trimmed OTP email', (tester) async {
    final gateway = FakeHouseholdGateway();
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' owner@example.com ');
    await tester.tap(find.widgetWithText(FilledButton, '发送登录链接'));
    await tester.pumpAndSettle();

    expect(gateway.sentEmail, 'owner@example.com');
  });

  testWidgets(
    'AuthGateScreen renders household bootstrap for signed-in users without households',
    (tester) async {
      final gateway = FakeHouseholdGateway(isAuthenticated: true);
      await tester.pumpWidget(_wrap(gateway));
      await tester.pumpAndSettle();

      expect(find.text('创建家庭配置'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '创建家庭'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
    },
  );

  testWidgets(
    'AuthGateScreen shows startup screen while signed-in session loads',
    (tester) async {
      final householdsCompleter = Completer<List<Household>>();
      final gateway = FakeHouseholdGateway(
        isAuthenticated: true,
        loadHouseholdsCompleter: householdsCompleter,
      );

      await tester.pumpWidget(_wrap(gateway));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
      expect(find.text('创建家庭配置'), findsNothing);

      householdsCompleter.complete(const [
        Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  testWidgets('AuthGateScreen creates first household', (tester) async {
    final gateway = FakeHouseholdGateway(isAuthenticated: true);
    await tester.pumpWidget(_wrap(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), ' Kunish Kitchen ');
    await tester.tap(find.widgetWithText(FilledButton, '创建家庭'));
    await tester.pumpAndSettle();

    expect(gateway.createdHouseholdName, 'Kunish Kitchen');
    expect(find.text('App Shell'), findsOneWidget);
    expect(find.text('创建家庭配置'), findsNothing);
  });

  testWidgets(
    'AuthGateScreen shows authenticated child after households load',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FakeHouseholdGateway(
            initialHouseholds: const [
              Household(
                id: 'household_1',
                name: 'Home',
                ownerId: 'owner_1',
                defaultStorageArea: 'fridge',
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);
    },
  );

  testWidgets(
    'AuthGateScreen exposes selected household id to authenticated child',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          FakeHouseholdGateway(
            initialHouseholds: const [
              Household(
                id: 'household_1',
                name: 'Home',
                ownerId: 'owner_1',
                defaultStorageArea: 'fridge',
              ),
            ],
          ),
          child: Consumer(
            builder: (context, ref, _) {
              return Text(ref.watch(selectedHouseholdIdProvider));
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('household_1'), findsOneWidget);
    },
  );

  testWidgets(
    'AuthGateScreen shows authenticated child after auth state changes',
    (tester) async {
      final gateway = FakeHouseholdGateway();
      await tester.pumpWidget(_wrap(gateway));
      await tester.pumpAndSettle();

      expect(find.text('登录 Fresh Pantry'), findsOneWidget);

      gateway.initialHouseholds = const [
        Household(
          id: 'household_1',
          name: 'Home',
          ownerId: 'owner_1',
          defaultStorageArea: 'fridge',
        ),
      ];
      gateway.emitAuthStateChange();
      await tester.pumpAndSettle();

      expect(find.text('App Shell'), findsOneWidget);
      expect(find.text('登录 Fresh Pantry'), findsNothing);

      await gateway.close();
    },
  );

  testWidgets('FreshPantryApp defaults to AuthGateScreen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          householdGatewayProvider.overrideWithValue(FakeHouseholdGateway()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AuthGateScreen), findsOneWidget);
    expect(find.text('登录 Fresh Pantry'), findsOneWidget);
  });
}

Widget _wrap(
  FakeHouseholdGateway gateway, {
  Widget child = const Text('App Shell'),
}) {
  return ProviderScope(
    overrides: [householdGatewayProvider.overrideWithValue(gateway)],
    child: MaterialApp(home: AuthGateScreen(authenticatedChild: child)),
  );
}
