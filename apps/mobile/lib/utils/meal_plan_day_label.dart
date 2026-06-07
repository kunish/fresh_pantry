import '../models/meal_plan_entry.dart';

/// 人类可读的计划日期标签:今天 / 明天 / 周一…周日。
///
/// 供日历屏与「加入计划」选择器共用,保证两处措辞一致。两个入参都会归一化到
/// 本地零点再比较天数差,避免时分秒导致 today/明天判断偏差。
String mealPlanDayLabel(DateTime day, DateTime today) {
  final d = MealPlanEntry.dateOnly(day);
  final base = MealPlanEntry.dateOnly(today);
  final diff = d.difference(base).inDays;
  if (diff == 0) return '今天';
  if (diff == 1) return '明天';
  const weekdays = ['一', '二', '三', '四', '五', '六', '日'];
  return '周${weekdays[d.weekday - 1]}';
}
