import 'package:fresh_pantry/models/scheduled_notification.dart';
import 'package:fresh_pantry/services/notification_service.dart';

/// A no-op NotificationService for widget/integration tests. Reports
/// permission as denied so notificationSyncProvider early-returns and
/// makes no actual scheduling calls.
class FakeNotificationService extends NotificationService {
  FakeNotificationService() : super();

  @override
  bool get isInitialized => true;

  @override
  bool get permissionGranted => false;

  @override
  Future<void> init({void Function(int notificationId)? onTap}) async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(ScheduledNotification n) async {}

  @override
  Future<void> syncAll(
    List<ScheduledNotification> next, {
    required List<int> previousIds,
  }) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  void debugSetState({required bool initialized, required bool permission}) {}
}
