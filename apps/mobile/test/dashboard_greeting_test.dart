import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/dashboard_greeting.dart';

void main() {
  group('dashboardGreetingFor', () {
    test('greets the chef according to the current hour', () {
      expect(dashboardGreetingFor(DateTime(2026, 4, 27, 5)), '早安，主厨。');
      expect(dashboardGreetingFor(DateTime(2026, 4, 27, 11)), '午安，主厨。');
      expect(dashboardGreetingFor(DateTime(2026, 4, 27, 14)), '下午好，主厨。');
      expect(dashboardGreetingFor(DateTime(2026, 4, 27, 18)), '晚上好，主厨。');
      expect(dashboardGreetingFor(DateTime(2026, 4, 27, 23)), '夜深了，主厨。');
    });
  });
}
