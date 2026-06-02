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
