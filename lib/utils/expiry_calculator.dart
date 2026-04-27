import '../models/ingredient.dart';

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

int calendarDaysBetween(DateTime start, DateTime end) {
  return _dateOnly(end).difference(_dateOnly(start)).inDays;
}

int daysUntilExpiry(DateTime expiryDate, {DateTime? now}) {
  return calendarDaysBetween(now ?? DateTime.now(), expiryDate);
}

double expiryFreshness({
  required DateTime expiryDate,
  required int totalShelfLifeDays,
  DateTime? now,
}) {
  if (totalShelfLifeDays <= 0) return 0.0;

  return (daysUntilExpiry(expiryDate, now: now) / totalShelfLifeDays).clamp(
    0.0,
    1.0,
  );
}

FreshnessState freshnessStateForExpiry({
  required double freshness,
  DateTime? expiryDate,
  DateTime? now,
}) {
  if (expiryDate != null && daysUntilExpiry(expiryDate, now: now) < 0) {
    return FreshnessState.expired;
  }
  if (freshness > 0.5) return FreshnessState.fresh;
  return FreshnessState.expiringSoon;
}
