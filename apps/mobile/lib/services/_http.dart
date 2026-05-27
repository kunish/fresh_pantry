import 'dart:async';

import 'package:http/http.dart' as http;

/// HTTP fetch with one retry on TimeoutException / ClientException, then
/// rethrows. Mirrors the retry+timeout pattern previously duplicated across
/// services (8s timeout, 1 retry, 500ms backoff).
///
/// If [client] is provided the caller owns its lifecycle; otherwise a
/// transient client is created and closed inside this function.
Future<http.Response> fetchWithRetry(
  Uri uri, {
  http.Client? client,
  Duration timeout = const Duration(seconds: 8),
  Duration retryDelay = const Duration(milliseconds: 500),
  int retryCount = 1,
  Map<String, String>? headers,
}) async {
  final httpClient = client ?? http.Client();
  try {
    for (var attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final response = await httpClient
            .get(uri, headers: headers)
            .timeout(timeout);
        return response;
      } on TimeoutException {
        if (attempt == retryCount) rethrow;
      } on http.ClientException {
        if (attempt == retryCount) rethrow;
      }
      await Future<void>.delayed(retryDelay);
    }
    throw StateError('Unreachable');
  } finally {
    if (client == null) httpClient.close();
  }
}
