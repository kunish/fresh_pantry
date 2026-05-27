import '../services/share_intent_service.dart';

/// Removes NUL characters often interleaved in UTF-16 clipboard payloads.
String stripNullCharacters(String text) => text.replaceAll('\u0000', '');

/// Recovers ASCII text from UTF-16 code units widened to `ascii << 8`.
///
/// Some iOS/macOS paste paths store `h` as U+6800 instead of U+0068, which
/// renders as CJK mojibake in a plain text field.
String decodeWidenedUtf16Ascii(String text) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    final hi = unit >> 8;
    final lo = unit & 0xFF;
    if (hi >= 0x20 && hi <= 0x7E && lo == 0) {
      buffer.writeCharCode(hi);
    } else if (unit <= 0x7F) {
      buffer.writeCharCode(unit);
    }
  }
  return buffer.toString();
}

bool looksLikeWidenedUtf16Ascii(String text) {
  var widened = 0;
  for (final unit in text.codeUnits) {
    final hi = unit >> 8;
    final lo = unit & 0xFF;
    if (hi >= 0x20 && hi <= 0x7E && lo == 0) {
      widened++;
    }
  }
  return widened >= 4;
}

/// Normalizes clipboard or pasted text so recipe URLs stay readable.
String normalizeClipboardText(String text) {
  final withoutNulls = stripNullCharacters(text);
  if (withoutNulls.isEmpty) return withoutNulls;

  final directUrl = extractUrl(withoutNulls);
  if (directUrl != null &&
      (withoutNulls.trim() == directUrl || looksLikeWidenedUtf16Ascii(withoutNulls))) {
    return directUrl;
  }

  final decoded = decodeWidenedUtf16Ascii(withoutNulls);
  if (decoded != withoutNulls) {
    final decodedUrl = extractUrl(decoded);
    if (decodedUrl != null) return decodedUrl;
    if (decoded.startsWith('http')) return decoded.trim();
  }

  return withoutNulls;
}

/// Keeps in-progress typing intact while fixing obvious paste mojibake.
String normalizePastedRecipeUrl(String text) {
  final normalized = normalizeClipboardText(text);
  if (normalized == text) {
    return ensureRecipeUrl(stripNullCharacters(text));
  }
  return ensureRecipeUrl(normalized);
}

/// Repairs common paste issues and adds https:// when a supported host is present.
String ensureRecipeUrl(String raw) {
  var text = normalizeClipboardText(raw.trim());
  if (text.isEmpty) return text;

  if (!text.startsWith('http')) {
    text = 'https://$text';
  }

  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return text;

  var host = uri.host.toLowerCase();
  if (host.startsWith('vw.')) {
    host = host.replaceFirst(RegExp(r'^vw\.'), 'www.');
  }

  if (host == uri.host.toLowerCase()) return text;
  return uri.replace(host: host).toString();
}
