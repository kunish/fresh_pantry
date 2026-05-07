import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_radius.dart';
import 'package:fresh_pantry/theme/app_spacing.dart';

void main() {
  group('AppSpacing tokens', () {
    test('canonical spacing values match contract', () {
      expect(AppSpacing.xs, 4);
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.md, 12);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xl, 20);
      expect(AppSpacing.xxl, 24);
      expect(AppSpacing.xxxl, 28);
      expect(AppSpacing.huge, 32);
    });
  });

  group('AppRadius tokens', () {
    test('canonical radius values match contract', () {
      expect(AppRadius.sm, 8);
      expect(AppRadius.md, 12);
      expect(AppRadius.lg, 16);
      expect(AppRadius.xl, 20);
      expect(AppRadius.xxl, 24);
      expect(AppRadius.pill, 999);
    });
  });
}
