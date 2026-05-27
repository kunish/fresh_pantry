import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../backend/backend_config_provider.dart';
import '../backend/supabase_client_provider.dart';
import '../providers/storage_service_provider.dart';
import '../storage/custom_recipe_repo.dart';
import '../storage/inventory_repo.dart';
import '../storage/shopping_repo.dart';
import '../sync/remote_pantry_repository.dart';
import 'household_models.dart';

const supabaseAuthRedirectUrl = 'com.kunish.freshpantry://signin-callback/';
const _preserveError = Object();

@visibleForTesting
String resolveSupabaseAuthRedirectUrl({bool isWeb = kIsWeb, Uri? webBaseUri}) {
  if (!isWeb) return supabaseAuthRedirectUrl;

  final uri = webBaseUri ?? Uri.base;
  if (uri.hasScheme &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.hasAuthority) {
    return '${uri.scheme}://${uri.authority}/';
  }

  return supabaseAuthRedirectUrl;
}

abstract class HouseholdGateway {
  Stream<void> get authStateChanges;
  bool get isAuthenticated;

  Future<void> sendOtp(String email);
  Future<List<Household>> loadHouseholds();
  Future<Household> createHousehold(String name);
  Future<void> uploadInitialData(String householdId);
  Future<String> createInvite({
    required String householdId,
    required String email,
  });
  Future<void> acceptInvite(String token);
}

class SupabaseHouseholdGateway implements HouseholdGateway {
  SupabaseHouseholdGateway(
    this._client,
    this._remoteRepository,
    this._inventoryRepo,
    this._shoppingRepo,
    this._customRecipeRepo,
  );

  final SupabaseClient _client;
  final RemotePantryRepository _remoteRepository;
  final InventoryRepo _inventoryRepo;
  final ShoppingRepo _shoppingRepo;
  final CustomRecipeRepo _customRecipeRepo;

  @override
  bool get isAuthenticated => _client.auth.currentUser != null;

  @override
  Stream<void> get authStateChanges {
    return _client.auth.onAuthStateChange
        .where((data) {
          return switch (data.event) {
            AuthChangeEvent.initialSession ||
            AuthChangeEvent.signedIn ||
            AuthChangeEvent.signedOut => true,
            _ => false,
          };
        })
        .map((_) {});
  }

  @override
  Future<void> sendOtp(String email) {
    return _client.auth.signInWithOtp(
      email: email,
      emailRedirectTo: resolveSupabaseAuthRedirectUrl(),
    );
  }

  @override
  Future<List<Household>> loadHouseholds() async {
    if (_client.auth.currentUser == null) return const [];
    return _remoteRepository.loadHouseholds();
  }

  @override
  Future<Household> createHousehold(String name) {
    return _remoteRepository.createHousehold(name);
  }

  @override
  Future<void> uploadInitialData(String householdId) async {
    await _remoteRepository.upsertInventory(
      householdId,
      _inventoryRepo.loadAll().map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertShopping(
      householdId,
      _shoppingRepo.loadAll().map((item) => item.toJson()).toList(),
    );
    await _remoteRepository.upsertCustomRecipes(
      householdId,
      _customRecipeRepo.loadAll().map((recipe) => recipe.toJson()).toList(),
    );
  }

  @override
  Future<String> createInvite({
    required String householdId,
    required String email,
  }) {
    return _remoteRepository.createInvite(
      householdId: householdId,
      email: email,
    );
  }

  @override
  Future<void> acceptInvite(String token) {
    return _remoteRepository.acceptInvite(token);
  }
}

class HouseholdSessionState {
  const HouseholdSessionState({
    this.email = '',
    this.isLoading = true,
    this.isSubmitting = false,
    this.isAuthenticated = false,
    this.error,
    this.households = const [],
  });

  final String email;
  final bool isLoading;
  final bool isSubmitting;
  final bool isAuthenticated;
  final String? error;
  final List<Household> households;

  HouseholdSessionState copyWith({
    String? email,
    bool? isLoading,
    bool? isSubmitting,
    bool? isAuthenticated,
    Object? error = _preserveError,
    List<Household>? households,
  }) {
    return HouseholdSessionState(
      email: email ?? this.email,
      isLoading: isLoading ?? this.isLoading,
      isSubmitting: isSubmitting ?? this.isSubmitting,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      error: identical(error, _preserveError) ? this.error : error as String?,
      households: households ?? this.households,
    );
  }
}

class HouseholdSessionController extends StateNotifier<HouseholdSessionState> {
  HouseholdSessionController(this._gateway)
    : super(const HouseholdSessionState()) {
    _authSubscription = _gateway.authStateChanges.listen(
      (_) => refreshHouseholds(),
      onError: (Object error, StackTrace stackTrace) {
        _setError(error);
      },
    );
  }

  final HouseholdGateway _gateway;
  StreamSubscription<void>? _authSubscription;

  Future<void> sendOtp(String email) async {
    final trimmed = email.trim();
    state = state.copyWith(email: trimmed, isSubmitting: true, error: null);
    try {
      await _gateway.sendOtp(trimmed);
      if (!mounted) return;
      state = state.copyWith(email: trimmed, isSubmitting: false, error: null);
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(
        email: trimmed,
        isSubmitting: false,
        error: error.toString(),
      );
    }
  }

  Future<void> refreshHouseholds() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final households = await _gateway.loadHouseholds();
      if (!mounted) return;
      state = state.copyWith(
        isLoading: false,
        error: null,
        isAuthenticated: _gateway.isAuthenticated,
        households: List.unmodifiable(households),
      );
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> createHousehold(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(error: '家庭名称不能为空');
      return;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final household = await _gateway.createHousehold(trimmed);
      await _gateway.uploadInitialData(household.id);
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        isAuthenticated: true,
        error: null,
        households: List.unmodifiable([household]),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  Future<String> createInvite(String householdId, String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      final error = ArgumentError.value(
        email,
        'email',
        'Invite email cannot be empty',
      );
      state = state.copyWith(error: error.toString());
      throw error;
    }

    state = state.copyWith(isSubmitting: true, error: null);
    try {
      final inviteUrl = await _gateway.createInvite(
        householdId: householdId,
        email: trimmedEmail,
      );
      if (!mounted) return inviteUrl;
      state = state.copyWith(isSubmitting: false, error: null);
      return inviteUrl;
    } catch (error) {
      if (mounted) {
        state = state.copyWith(isSubmitting: false, error: error.toString());
      }
      rethrow;
    }
  }

  Future<void> acceptInvite(String token) async {
    final trimmedToken = token.trim();
    state = state.copyWith(isSubmitting: true, error: null);
    try {
      await _gateway.acceptInvite(trimmedToken);
      final households = await _gateway.loadHouseholds();
      if (!mounted) return;
      state = state.copyWith(
        isSubmitting: false,
        error: null,
        isAuthenticated: _gateway.isAuthenticated,
        households: List.unmodifiable(households),
      );
    } catch (error) {
      if (!mounted) return;
      state = state.copyWith(isSubmitting: false, error: error.toString());
    }
  }

  void _setError(Object error) {
    if (!mounted) return;
    state = state.copyWith(isLoading: false, error: error.toString());
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}

final householdGatewayProvider = Provider<HouseholdGateway>((ref) {
  final client = ref.read(supabaseClientProvider);
  final backendConfig = ref.read(backendConfigProvider);
  return SupabaseHouseholdGateway(
    client,
    SupabaseRemotePantryRepository(
      client,
      apiBaseUrl: backendConfig.apiBaseUrl,
    ),
    ref.read(inventoryRepoProvider),
    ref.read(shoppingRepoProvider),
    ref.read(customRecipeRepoProvider),
  );
});

final householdSessionControllerProvider =
    StateNotifierProvider<HouseholdSessionController, HouseholdSessionState>((
      ref,
    ) {
      return HouseholdSessionController(ref.read(householdGatewayProvider));
    });
