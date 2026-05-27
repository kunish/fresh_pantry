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

    test('locks the rotation order against the placeholder list', () {
      // The placeholder rotation is keyed off the day number since
      // 1970-01-01 modulo the placeholder list length (5 strings).
      // 2026-04-27 → 20570 days → 20570 % 5 == 0 → first placeholder.
      const placeholders = [
        '看看今天有哪些食材值得先安排。',
        '从库存里找一点下一餐的灵感。',
        '把新鲜食材留给最合适的一餐。',
        '先整理食材，再决定今天吃什么。',
        '让冰箱和食品柜保持刚刚好的节奏。',
      ];
      final base = DateTime(2026, 4, 27);
      for (var offset = 0; offset < placeholders.length; offset++) {
        final day = base.add(Duration(days: offset));
        expect(
          dashboardSubtitleFor(day),
          placeholders[offset % placeholders.length],
          reason: 'unexpected placeholder for ${day.toIso8601String()}',
        );
      }
      // After a full cycle the subtitle wraps back to the first entry.
      expect(
        dashboardSubtitleFor(base.add(Duration(days: placeholders.length))),
        placeholders.first,
      );
    });
  });
}
