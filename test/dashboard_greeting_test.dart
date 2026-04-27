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

  group('dashboardSubtitleFor', () {
    test('uses rotating placeholder copy instead of fixed fake stats', () {
      final today = dashboardSubtitleFor(DateTime(2026, 4, 27));
      final tomorrow = dashboardSubtitleFor(DateTime(2026, 4, 28));

      expect(today, isNot('您的食材库已备齐84%，本周食材已精心策划。'));
      expect(today, isNot(contains('84%')));
      expect(tomorrow, isNot(today));
      expect(dashboardSubtitleFor(DateTime(2026, 4, 27, 23, 59)), today);
    });
  });
}
