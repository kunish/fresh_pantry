import 'package:fresh_pantry/household/household_models.dart';
import 'package:fresh_pantry/household/household_session_controller.dart';

const stubInviteUrl =
    'https://api.fresh-pantry.kunish.eu.org/invite/abcDEF123_-';

class HouseholdGatewayStub implements HouseholdGateway {
  HouseholdGatewayStub({
    this.households = const [],
    this.inviteUrl = stubInviteUrl,
    this.isAuthenticated = false,
    bool emitInitialAuthState = false,
  }) : _authStateChanges = emitInitialAuthState
           ? Stream<void>.value(null)
           : const Stream<void>.empty();

  final List<Household> households;
  final String inviteUrl;
  @override
  final bool isAuthenticated;
  final Stream<void> _authStateChanges;
  var inviteHouseholdId = '';
  var inviteEmail = '';
  var acceptedToken = '';

  @override
  Stream<void> get authStateChanges => _authStateChanges;

  @override
  Future<void> sendOtp(String email) async {}

  @override
  Future<List<Household>> loadHouseholds() async {
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
    inviteHouseholdId = householdId;
    inviteEmail = email;
    return inviteUrl;
  }

  @override
  Future<void> acceptInvite(String token) async {
    acceptedToken = token;
  }
}
