/// Normalizes an OpenAI-compatible API base URL for [AiClient].
///
/// Accepts common user inputs such as the host root, a `/v1` base, or a full
/// `/v1/chat/completions` endpoint pasted by mistake.
String normalizeAiBaseUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return url;

  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }

  const chatSuffix = '/chat/completions';
  if (url.endsWith(chatSuffix)) {
    url = url.substring(0, url.length - chatSuffix.length);
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
  }

  if (!url.endsWith('/v1')) {
    url = '$url/v1';
  }

  return url;
}
