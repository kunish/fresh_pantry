class BackendConfigException implements Exception {
  const BackendConfigException(this.message);

  final String message;

  @override
  String toString() => 'BackendConfigException: $message';
}

class BackendConfig {
  const BackendConfig({
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.apiBaseUrl,
  });

  factory BackendConfig.fromEnvironment() {
    return const BackendConfig(
      supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      apiBaseUrl: String.fromEnvironment(
        'FRESH_PANTRY_API_BASE_URL',
        defaultValue: 'https://api.fresh-pantry.kunish.eu.org',
      ),
    ).validate();
  }

  final String supabaseUrl;
  final String supabasePublishableKey;
  final String apiBaseUrl;

  BackendConfig validate() {
    if (supabaseUrl.trim().isEmpty) {
      throw const BackendConfigException('SUPABASE_URL is required');
    }
    if (!_isHttpUrl(supabaseUrl)) {
      throw BackendConfigException('SUPABASE_URL is invalid: $supabaseUrl');
    }

    if (supabasePublishableKey.trim().isEmpty) {
      throw const BackendConfigException(
        'SUPABASE_PUBLISHABLE_KEY is required',
      );
    }

    if (!_isHttpUrl(apiBaseUrl)) {
      throw BackendConfigException(
        'FRESH_PANTRY_API_BASE_URL is invalid: $apiBaseUrl',
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
