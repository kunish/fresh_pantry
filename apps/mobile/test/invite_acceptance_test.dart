import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

class InviteRecordingGateway implements HouseholdGateway {
  final authStateController = StreamController<void>.broadcast();
  final households = <Household>[
    const Household(
      id: 'household_1',
      name: 'Home',
      ownerId: 'owner_1',
      defaultStorageArea: 'fridge',
    ),
  ];
  var acceptedToken = '';
  var inviteHouseholdId = '';
  var inviteEmail = '';
  var loadCount = 0;
  Object? acceptInviteError;
  Object? createInviteError;

  @override
  bool get isAuthenticated => true;

  @override
  Stream<void> get authStateChanges => authStateController.stream;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<List<Household>> loadHouseholds() async {
    loadCount += 1;
    return households;
  }

  @override
  Future<Household> createHousehold(String name) {
    throw UnimplementedError('Not needed by these tests.');
  }

  @override
  Future<void> uploadInitialData(String householdId) async {}

  @override
  Future<String> createInvite({
    required String householdId,
    required String email,
  }) async {
    if (createInviteError != null) throw createInviteError!;
    inviteHouseholdId = householdId;
    inviteEmail = email;
    return 'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-';
  }

  @override
  Future<void> acceptInvite(String token) async {
    if (acceptInviteError != null) throw acceptInviteError!;
    acceptedToken = token;
  }

  Future<void> close() {
    return authStateController.close();
  }
}

void main() {
  test('createInvite trims email before delegating', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    final inviteUrl = await controller.createInvite(
      'household_1',
      ' member@example.com ',
    );

    expect(
      inviteUrl,
      'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-',
    );
    expect(gateway.inviteHouseholdId, 'household_1');
    expect(gateway.inviteEmail, 'member@example.com');
    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('acceptInvite trims token and refreshes households', () async {
    final gateway = InviteRecordingGateway();
    final controller = HouseholdSessionController(gateway);

    await controller.acceptInvite(' abcDEF123_- ');

    expect(gateway.acceptedToken, 'abcDEF123_-');
    expect(gateway.loadCount, 1);
    expect(controller.state.households.single.id, 'household_1');
    expect(controller.state.isSubmitting, isFalse);

    controller.dispose();
    await gateway.close();
  });

  test('acceptInvite exposes gateway errors', () async {
    final gateway = InviteRecordingGateway()
      ..acceptInviteError = StateError('invite unavailable');
    final controller = HouseholdSessionController(gateway);

    await controller.acceptInvite('abcDEF123_-');

    expect(controller.state.error, contains('invite unavailable'));
    expect(controller.state.isSubmitting, isFalse);
    expect(gateway.loadCount, 0);

    controller.dispose();
    await gateway.close();
  });
}
