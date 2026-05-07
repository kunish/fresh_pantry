import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/json_cast.dart';

void main() {
  group('asJsonMap', () {
    test('returns Map<String, dynamic> input as-is', () {
      final input = <String, dynamic>{'a': 1, 'b': 'two'};
      expect(asJsonMap(input), same(input));
    });

    test('returns null for List input', () {
      expect(asJsonMap(<dynamic>[1, 2, 3]), isNull);
    });

    test('returns null for null input', () {
      expect(asJsonMap(null), isNull);
    });

    test('returns null for String input', () {
      expect(asJsonMap('not a map'), isNull);
    });

    test('returns null for raw Map (non-string-keyed)', () {
      // Maps not statically typed as Map<String, dynamic> are rejected to
      // keep callers free of unchecked casts.
      final raw = <Object, dynamic>{'a': 1};
      expect(asJsonMap(raw), isNull);
    });
  });

  group('asJsonList', () {
    test('returns List<dynamic> input as-is', () {
      final input = <dynamic>[1, 'two', null];
      expect(asJsonList(input), same(input));
    });

    test('returns null for Map input', () {
      expect(asJsonList(<String, dynamic>{'a': 1}), isNull);
    });

    test('returns null for null', () {
      expect(asJsonList(null), isNull);
    });
  });

  group('asJsonString', () {
    test('returns String input as-is', () {
      expect(asJsonString('hello'), 'hello');
    });

    test('returns null for int input', () {
      expect(asJsonString(42), isNull);
    });

    test('returns null for null', () {
      expect(asJsonString(null), isNull);
    });
  });
}
