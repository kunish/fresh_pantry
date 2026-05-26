import 'dart:convert';

import 'package:http/http.dart' as http;

import '../utils/clipboard_text.dart';
import 'ai_client.dart';

typedef RecipePageFetcherFn = Future<String> Function(String url);

const _mobileSafariUserAgent =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1';

class RecipePageFetcher {
  const RecipePageFetcher._();

  static Future<String> fetchText(String url, {http.Client? client}) async {
    final normalizedUrl = ensureRecipeUrl(url);
    final uri = Uri.parse(normalizedUrl);
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      final response = await c
          .get(
            uri,
            headers: const {
              'User-Agent': _mobileSafariUserAgent,
              'Accept': 'text/html,application/xhtml+xml',
              'Accept-Language': 'zh-CN,zh;q=0.9',
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw AiNetworkException('网页抓取失败 (${response.statusCode})');
      }

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);
      if (_looksLikeCaptchaPage(html, response.request?.url ?? uri)) {
        throw const AiNetworkException('目标网站需要人机验证，暂时无法自动抓取');
      }

      final text = extractRecipePageText(html);
      if (text.trim().isEmpty) {
        throw const AiParseException('网页中没有可解析的食谱内容');
      }
      return text;
    } on AiException {
      rethrow;
    } on http.ClientException catch (e) {
      throw AiNetworkException('网页抓取失败：${e.message}');
    } finally {
      if (ownClient) c.close();
    }
  }
}

bool _looksLikeCaptchaPage(String html, Uri finalUri) {
  final lower = html.toLowerCase();
  return finalUri.path.contains('humancheck') ||
      lower.contains('humancheck_captcha') ||
      lower.contains('auth/humancheck');
}

String extractRecipePageText(String html) {
  final parts = <String>[];

  final titleMatch = RegExp(r'<title[^>]*>([^<]+)', caseSensitive: false).firstMatch(html);
  final title = _decodeHtmlEntities(titleMatch?.group(1)?.trim());
  if (title != null && title.isNotEmpty) {
    parts.add('标题: $title');
  }

  final descriptionMatch = RegExp(
    r'''name=["']description["']\s+content=["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  final description = _decodeHtmlEntities(descriptionMatch?.group(1)?.trim());
  if (description != null && description.isNotEmpty) {
    parts.add('摘要: $description');
  }

  var body = html;
  body = body.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), ' ');
  body = body.replaceAll(RegExp(r'<style[\s\S]*?</style>', caseSensitive: false), ' ');
  body = body.replaceAll(RegExp(r'<[^>]+>'), ' ');
  body = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (body.length > 80_000) {
    body = body.substring(0, 80_000);
  }
  if (body.isNotEmpty) {
    parts.add('正文: $body');
  }

  return parts.join('\n\n');
}

String? _decodeHtmlEntities(String? value) {
  if (value == null || value.isEmpty) return value;
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ');
}
