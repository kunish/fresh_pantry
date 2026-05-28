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
    required this.environment,
  });

  factory SentryConfig.fromEnvironment() {
    const sampleRateValue = String.fromEnvironment(
      'SENTRY_TRACES_SAMPLE_RATE',
      defaultValue: '1.0',
    );
    return SentryConfig(
      dsn: const String.fromEnvironment(
        'SENTRY_DSN',
        defaultValue: defaultSentryDsn,
      ),
      tracesSampleRate: double.tryParse(sampleRateValue) ?? double.nan,
      environment: const String.fromEnvironment('SENTRY_ENVIRONMENT'),
    ).validate();
  }

  final String dsn;
  final double tracesSampleRate;
  final String environment;

  SentryConfig validate() {
    if (dsn.trim().isNotEmpty && !_isHttpUrl(dsn)) {
      throw SentryConfigException('SENTRY_DSN is invalid: $dsn');
    }

    if (!tracesSampleRate.isFinite ||
        tracesSampleRate < 0 ||
        tracesSampleRate > 1) {
      throw SentryConfigException(
        'SENTRY_TRACES_SAMPLE_RATE must be between 0 and 1: '
        '$tracesSampleRate',
      );
    }

    return this;
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
