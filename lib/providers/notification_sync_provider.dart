import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/expiry_scheduler.dart';
import 'inventory_provider.dart';
import 'notification_service_provider.dart';
import 'reminder_settings_provider.dart';

class NotificationSyncNotifier extends Notifier<List<int>> {
  List<int> _previousIds = const [];

  @override
  List<int> build() {
    // Subscribe to both providers so changes invalidate this provider.
    ref.watch(inventoryProvider);
    ref.watch(reminderSettingsProvider);

    // Trigger async resync after this build completes.
    Future.microtask(_resync);

    // Return the cached previous IDs so state survives across rebuilds.
    return _previousIds;
  }

  Future<void> _resync() async {
    final inventory = ref.read(inventoryProvider);
    final settings = ref.read(reminderSettingsProvider);
    final service = ref.read(notificationServiceProvider);
    if (!service.permissionGranted) return;
    final next = ExpiryScheduler.compute(
      inventory: inventory,
      settings: settings,
      now: DateTime.now(),
    );
    final nextIds = next.map((n) => n.id).toList();
    await service.syncAll(next, previousIds: _previousIds);
    _previousIds = nextIds;
    if (state != nextIds) state = nextIds;
  }
}

final notificationSyncProvider =
    NotifierProvider<NotificationSyncNotifier, List<int>>(
        NotificationSyncNotifier.new);
