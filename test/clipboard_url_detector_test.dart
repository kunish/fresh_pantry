// test/clipboard_url_detector_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';

void main() {
  group('ClipboardUrlDetector', () {
    test('returns null when clipboard does not contain http(s) URL', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'just plain text, no link',
      );
      expect(await d.peek(), isNull);
    });

    test('extracts first http(s) URL from text', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => '看看这个: https://lanfanapp.com/recipe/15978 很赞',
      );
      expect(await d.peek(), 'https://lanfanapp.com/recipe/15978');
    });

    test('ignores URLs from non-whitelisted hosts', () async {
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async =>
            'https://docs.flutter.dev/release/breaking-changes/uiscenedelegate',
      );
      expect(await d.peek(), isNull);
    });

    test('ignored URL is suppressed within cooldown window', () async {
      var now = DateTime(2026, 5, 8, 12, 0, 0);
      final d = ClipboardUrlDetector(
        ignoreCooldown: const Duration(minutes: 30),
        clipboardReader: () async => 'https://lanfanapp.com/recipe/1',
        clock: () => now,
      );
      d.markIgnored('https://lanfanapp.com/recipe/1');
      expect(await d.peek(), isNull);

      now = now.add(const Duration(minutes: 31));
      expect(await d.peek(), 'https://lanfanapp.com/recipe/1');
    });
  });

  group('extractUrl', () {
    test('returns null for plain text', () {
      expect(extractUrl('no link here'), isNull);
    });
    test('grabs first URL from mixed text', () {
      expect(extractUrl('看 https://lanfanapp.com/recipe/15978 这个'),
          'https://lanfanapp.com/recipe/15978');
    });
    test('accepts xiachufang.com', () {
      expect(extractUrl('https://www.xiachufang.com/recipe/12345'),
          'https://www.xiachufang.com/recipe/12345');
    });
    test('accepts subdomain of whitelisted host', () {
      expect(extractUrl('https://m.lanfanapp.com/r/1'),
          'https://m.lanfanapp.com/r/1');
    });
    test('rejects lookalike domain that suffix-matches naively', () {
      // `evil-lanfanapp.com` would pass a naive `endsWith("lanfanapp.com")`,
      // but the host check requires exact match or a `.<host>` boundary.
      expect(extractUrl('https://evil-lanfanapp.com/recipe/1'), isNull);
    });
    test('rejects unsupported source like Flutter docs', () {
      expect(
          extractUrl(
              'https://docs.flutter.dev/release/breaking-changes/uiscenedelegate#migration-guide-for-flutter-plugins'),
          isNull);
    });
  });
}
