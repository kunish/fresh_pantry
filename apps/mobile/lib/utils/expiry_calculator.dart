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

/// Items within this many calendar days of expiry are [FreshnessState.urgent]
/// regardless of their freshness ratio (a short-shelf item can read "fresh" by
/// ratio while expiring tomorrow).
const urgentWithinDays = 2;

FreshnessState freshnessStateForExpiry({
  required double freshness,
  DateTime? expiryDate,
  DateTime? now,
}) {
  if (expiryDate != null) {
    final days = daysUntilExpiry(expiryDate, now: now);
    if (days < 0) return FreshnessState.expired;
    if (days <= urgentWithinDays) return FreshnessState.urgent;
  }
  if (freshness > 0.5) return FreshnessState.fresh;
  return FreshnessState.expiringSoon;
}

String expiryLabelFor(DateTime expiryDate, {DateTime? now}) {
  final days = daysUntilExpiry(expiryDate, now: now);
  if (days < 0) return '已过期${-days}天';
  if (days == 0) return '今天过期';
  if (days == 1) return '明天过期';
  return '$days天后过期';
}
