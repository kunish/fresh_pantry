import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/config/backend_config.dart';

void main() {
  test('BackendConfig validates required values', () {
    expect(
      () => const BackendConfig(
        supabaseUrl: '',
        supabasePublishableKey: 'key',
        apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );

    expect(
      () => const BackendConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: ' ',
        apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );
  });

  test('BackendConfig rejects invalid URLs', () {
    expect(
      () => const BackendConfig(
        supabaseUrl: 'not-a-url',
        supabasePublishableKey: 'publishable',
        apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );

    expect(
      () => const BackendConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable',
        apiBaseUrl: 'not-a-url',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );

    expect(
      () => const BackendConfig(
        supabaseUrl: 'https://',
        supabasePublishableKey: 'publishable',
        apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );

    expect(
      () => const BackendConfig(
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable',
        apiBaseUrl: 'ftp://api.fresh-pantry.kunish.eu.org',
      ).validate(),
      throwsA(isA<BackendConfigException>()),
    );
  });

  test('BackendConfig accepts complete values', () {
    const config = BackendConfig(
      supabaseUrl: 'https://example.supabase.co',
      supabasePublishableKey: 'publishable',
      apiBaseUrl: 'https://api.fresh-pantry.kunish.eu.org',
    );

    expect(config.validate(), config);
  });
}
