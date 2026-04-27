import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/expiry_calculator.dart';

void main() {
  group('daysUntilExpiry', () {
    test('counts tomorrow as one day regardless of current time', () {
      final now = DateTime(2026, 4, 24, 16, 30);
      final tomorrowFromDatePicker = DateTime(2026, 4, 25);

      expect(daysUntilExpiry(tomorrowFromDatePicker, now: now), 1);
    });
  });

  group('expiryFreshness', () {
    test('keeps full freshness for a seven day shelf life on the same day', () {
      final createdAt = DateTime(2026, 4, 24, 9);
      final savedAt = DateTime(2026, 4, 24, 17);
      final expiryDate = createdAt.add(const Duration(days: 7));

      expect(
        expiryFreshness(
          expiryDate: expiryDate,
          totalShelfLifeDays: 7,
          now: savedAt,
        ),
        1.0,
      );
    });
  });
}
