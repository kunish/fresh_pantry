import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/config/sentry_config.dart';

void main() {
  test('SentryConfig accepts the checked-in project DSN', () {
    const config = SentryConfig(
      dsn: defaultSentryDsn,
      tracesSampleRate: 1,
      environment: '',
    );

    expect(config.validate(), config);
  });

  test('SentryConfig allows an empty DSN to disable event delivery', () {
    const config = SentryConfig(
      dsn: '',
      tracesSampleRate: 0,
      environment: 'local',
    );

    expect(config.validate(), config);
  });

  test('SentryConfig rejects invalid DSNs', () {
    expect(
      () => const SentryConfig(
        dsn: 'not-a-url',
        tracesSampleRate: 1,
        environment: '',
      ).validate(),
      throwsA(isA<SentryConfigException>()),
    );
  });

  test('SentryConfig rejects invalid trace sample rates', () {
    for (final sampleRate in const [-0.1, 1.1]) {
      expect(
        () => SentryConfig(
          dsn: defaultSentryDsn,
          tracesSampleRate: sampleRate,
          environment: '',
        ).validate(),
        throwsA(isA<SentryConfigException>()),
      );
    }
  });
}
