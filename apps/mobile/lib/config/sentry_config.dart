const defaultSentryDsn =
    'https://21d545f97f6b73ed79a31c666318ba7f@o848334.ingest.us.sentry.io/4511468203147264';

class SentryConfigException implements Exception {
  const SentryConfigException(this.message);

  final String message;

  @override
  String toString() => 'SentryConfigException: $message';
}

class SentryConfig {
  const SentryConfig({
    required this.dsn,
    required this.tracesSampleRate,
    required this.replaySessionSampleRate,
    required this.replayOnErrorSampleRate,
    required this.environment,
  });

  factory SentryConfig.fromEnvironment() {
    const tracesSampleRateValue = String.fromEnvironment(
      'SENTRY_TRACES_SAMPLE_RATE',
      defaultValue: '1.0',
    );
    const replaySessionSampleRateValue = String.fromEnvironment(
      'SENTRY_REPLAY_SESSION_SAMPLE_RATE',
      defaultValue: '1.0',
    );
    const replayOnErrorSampleRateValue = String.fromEnvironment(
      'SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE',
      defaultValue: '1.0',
    );
    return SentryConfig(
      dsn: const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: defaultSentryDsn,
      ),
      tracesSampleRate: _parseSampleRate(tracesSampleRateValue),
      replaySessionSampleRate: _parseSampleRate(replaySessionSampleRateValue),
      replayOnErrorSampleRate: _parseSampleRate(replayOnErrorSampleRateValue),
      environment: const String.fromEnvironment('SENTRY_ENVIRONMENT'),
    ).validate();
  }

  final String dsn;
  final double tracesSampleRate;
  final double replaySessionSampleRate;
  final double replayOnErrorSampleRate;
  final String environment;

  SentryConfig validate() {
    if (dsn.trim().isNotEmpty && !_isHttpUrl(dsn)) {
      throw SentryConfigException('SENTRY_DSN is invalid: $dsn');
    }

    _validateSampleRate('SENTRY_TRACES_SAMPLE_RATE', tracesSampleRate);
    _validateSampleRate(
      'SENTRY_REPLAY_SESSION_SAMPLE_RATE',
      replaySessionSampleRate,
    );
    _validateSampleRate(
      'SENTRY_REPLAY_ON_ERROR_SAMPLE_RATE',
      replayOnErrorSampleRate,
    );

    return this;
  }

  static double _parseSampleRate(String value) {
    return double.tryParse(value) ?? double.nan;
  }

  static void _validateSampleRate(String name, double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw SentryConfigException('$name must be between 0 and 1: $value');
    }
  }

  static bool _isHttpUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.hasScheme &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.hasAuthority &&
        uri.host.isNotEmpty;
  }
}
