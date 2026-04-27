String dashboardGreetingFor(DateTime now) {
  final hour = now.hour;

  if (hour >= 5 && hour < 11) {
    return '早安，主厨。';
  }
  if (hour >= 11 && hour < 14) {
    return '午安，主厨。';
  }
  if (hour >= 14 && hour < 18) {
    return '下午好，主厨。';
  }
  if (hour >= 18 && hour < 23) {
    return '晚上好，主厨。';
  }
  return '夜深了，主厨。';
}

const _dashboardSubtitlePlaceholders = [
  '看看今天有哪些食材值得先安排。',
  '从库存里找一点下一餐的灵感。',
  '把新鲜食材留给最合适的一餐。',
  '先整理食材，再决定今天吃什么。',
  '让冰箱和食品柜保持刚刚好的节奏。',
];

String dashboardSubtitleFor(DateTime now) {
  final dayNumber =
      DateTime.utc(
        now.year,
        now.month,
        now.day,
      ).difference(DateTime.utc(1970)).inDays;

  return _dashboardSubtitlePlaceholders[dayNumber.remainder(
    _dashboardSubtitlePlaceholders.length,
  )];
}
