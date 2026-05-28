import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/backend_config_provider.dart';
import '../backend/supabase_client_provider.dart';
import '../providers/storage_service_provider.dart';
import 'remote_pantry_repository.dart';
import 'sync_coordinator.dart';

final selectedHouseholdIdProvider = Provider<String>((ref) => '');

final syncClientIdProvider = Provider<String>((ref) => 'local-client');

final remotePantryRepositoryProvider = Provider<RemotePantryRepository>((ref) {
  final backendConfig = ref.read(backendConfigProvider);
  return SupabaseRemotePantryRepository(
    ref.read(supabaseClientProvider),
    apiBaseUrl: backendConfig.apiBaseUrl,
  );
});

final syncCoordinatorProvider = Provider<SyncCoordinator>((ref) {
  final remote = ref.read(remotePantryRepositoryProvider);
  if (remote is! RemoteSyncGateway) {
    throw StateError('Remote pantry repository does not support sync pushes.');
  }
  return SyncCoordinator(
    outbox: ref.read(syncOutboxRepoProvider),
    remote: remote as RemoteSyncGateway,
  );
});

final syncPushPendingProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    try {
      await ref.read(syncCoordinatorProvider).pushPending();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry.sync',
          context: ErrorDescription('while pushing household sync operations'),
        ),
      );
    }
  };
});
