import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/ai_base_url.dart';

void main() {
  group('normalizeAiBaseUrl', () {
    test('appends /v1 to host-only URL', () {
      expect(
        normalizeAiBaseUrl('https://cpa.kunish.eu.org'),
        'https://cpa.kunish.eu.org/v1',
      );
    });

    test('preserves existing /v1 suffix', () {
      expect(
        normalizeAiBaseUrl('https://cpa.kunish.eu.org/v1'),
        'https://cpa.kunish.eu.org/v1',
      );
    });

    test('strips trailing slash before normalizing', () {
      expect(
        normalizeAiBaseUrl('https://cpa.kunish.eu.org/v1/'),
        'https://cpa.kunish.eu.org/v1',
      );
    });

    test('strips pasted chat/completions endpoint', () {
      expect(
        normalizeAiBaseUrl('https://cpa.kunish.eu.org/v1/chat/completions'),
        'https://cpa.kunish.eu.org/v1',
      );
    });

    test('returns empty string unchanged', () {
      expect(normalizeAiBaseUrl('   '), '');
    });

    test('does not append /v1 when /v1/ already appears mid-path', () {
      expect(
        normalizeAiBaseUrl('https://host/v1/openai'),
        'https://host/v1/openai',
      );
    });
  });
}
