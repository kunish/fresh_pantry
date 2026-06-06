import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/quantity_text.dart';

void main() {
  group('parseLeadingQuantity', () {
    test('splits magnitude and unit with a space', () {
      final r = parseLeadingQuantity('3 个');
      expect(r?.magnitude, '3');
      expect(r?.remainder, '个');
    });

    test('splits magnitude and unit without a space', () {
      final r = parseLeadingQuantity('1.5kg');
      expect(r?.magnitude, '1.5');
      expect(r?.remainder, 'kg');
    });

    test('bare number yields empty remainder', () {
      final r = parseLeadingQuantity('5');
      expect(r?.magnitude, '5');
      expect(r?.remainder, '');
    });

    test('no leading number yields null', () {
      expect(parseLeadingQuantity('约一把'), isNull);
      expect(parseLeadingQuantity(''), isNull);
    });
  });

  group('formatQuantity', () {
    test('whole doubles render as ints', () {
      expect(formatQuantity(3), '3');
      expect(formatQuantity(0), '0');
      expect(formatQuantity(8), '8');
    });

    test('fractional doubles keep their decimals', () {
      expect(formatQuantity(1.5), '1.5');
      expect(formatQuantity(0.25), '0.25');
    });

    test('binary float artifacts are rounded away', () {
      // The whole reason for the 2-decimal guard: raw toString() of these sums
      // leaks "1.2000000000000002" / "0.30000000000000004".
      expect(formatQuantity(1.1 + 0.1), '1.2');
      expect(formatQuantity(0.1 + 0.2), '0.3');
    });
  });
}
