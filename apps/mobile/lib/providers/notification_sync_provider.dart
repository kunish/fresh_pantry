import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ingredient.dart';
import '../models/reminder_settings.dart';
import '../models/scheduled_notification.dart';
import '../services/expiry_scheduler.dart';
import 'inventory_provider.dart';
import 'notification_service_provider.dart';
import 'reminder_settings_provider.dart';
import 'storage_service_provider.dart';

typedef ExpiryScheduleComputer =
    List<ScheduledNotification> Function({
      required List<Ingredient> inventory,
      required ReminderSettings settings,
      required DateTime now,
    });

final expiryScheduleComputerProvider = Provider<ExpiryScheduleComputer>(
  (ref) => ExpiryScheduler.compute,
);

const _scheduledIdsKey = 'notification_sync_scheduled_ids_v1';

List<int> _loadPersistedIds(SharedPreferences prefs) {
  final raw = prefs.getString(_scheduledIdsKey);
  if (raw == null) return const [];
  try {
    final list = jsonDecode(raw) as List<dynamic>;
    return list.cast<int>();
  } catch (_) {
    return const [];
  }
}

Future<void> _persistIds(SharedPreferences prefs, List<int> ids) async {
  await prefs.setString(_scheduledIdsKey, jsonEncode(ids));
}

class NotificationSyncNotifier extends Notifier<List<int>> {
  // Single-flight guard: non-null while a resync Future is in progress.
  Future<void>? _inflight;

  @override
  List<int> build() {
    // Subscribe to both providers so changes invalidate this provider.
    ref.watch(inventoryProvider);
    ref.watch(reminderSettingsProvider);

    // Trigger async resync after this build completes.
    Future.microtask(_resyncSafely);

    // Seed from SharedPreferences on first build so stale OS notifications
    // scheduled in a prior session can be cancelled on the first resync.
    if (stateOrNull != null) return stateOrNull!;
    final prefs = ref.read(sharedPreferencesProvider);
    return _loadPersistedIds(prefs);
  }

  Future<void> _resyncSafely() async {
    // Single-flight: if a resync is already running, skip — the running one
    // already holds the current state snapshot.
    if (_inflight != null) return;
    final work = _resync();
    _inflight = work;
    try {
      await work;
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'fresh_pantry',
          context: ErrorDescription('while syncing expiry notifications'),
        ),
      );
    } finally {
      _inflight = null;
    }
  }

  Future<void> _resync() async {
    final previousIds = List<int>.unmodifiable(state);
    final inventory = ref.read(inventoryProvider);
    final settings = ref.read(reminderSettingsProvider);
    final service = ref.read(notificationServiceProvider);
    if (!service.permissionGranted) return;
    final next = ref.read(expiryScheduleComputerProvider)(
      inventory: inventory,
      settings: settings,
      now: DateTime.now(),
    );
    final nextIds = next.map((n) => n.id).toList();
    await service.syncAll(next, previousIds: previousIds);
    // The provider can be disposed while syncAll awaits; touching ref after that
    // gap throws UnmountedRefException, so bail instead of crashing the resync.
    if (!ref.mounted) return;
    final prefs = ref.read(sharedPreferencesProvider);
    await _persistIds(prefs, nextIds);
    if (!ref.mounted) return;
    if (!listEquals(state, nextIds)) state = nextIds;
  }
}

final notificationSyncProvider =
    NotifierProvider<NotificationSyncNotifier, List<int>>(
      NotificationSyncNotifier.new,
    );
