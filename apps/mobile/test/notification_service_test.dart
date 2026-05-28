import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/notification_service.dart';

void main() {
  test('NotificationService starts uninitialized', () {
    final svc = NotificationService();
    expect(svc.isInitialized, isFalse);
    expect(svc.permissionGranted, isFalse);
  });

  test('checkPermission returns false and leaves permissionGranted false when not initialized', () async {
    final svc = NotificationService();
    final result = await svc.checkPermission();
    expect(result, isFalse);
    expect(svc.permissionGranted, isFalse);
  });

  test('debugSetState allows forcing permissionGranted for tests', () {
    final svc = NotificationService();
    svc.debugSetState(initialized: true, permission: true);
    expect(svc.isInitialized, isTrue);
    expect(svc.permissionGranted, isTrue);
  });
}
