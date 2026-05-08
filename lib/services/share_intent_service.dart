import 'package:flutter/services.dart';

typedef ClipboardReader = Future<String?> Function();
typedef Clock = DateTime Function();

Future<String?> _defaultClipboardRead() async {
  final data = await Clipboard.getData('text/plain');
  return data?.text;
}

class ClipboardUrlDetector {
  ClipboardUrlDetector({
    this.ignoreCooldown = const Duration(minutes: 30),
    ClipboardReader? clipboardReader,
    Clock? clock,
  })  : _read = clipboardReader ?? _defaultClipboardRead,
        _clock = clock ?? DateTime.now;

  final Duration ignoreCooldown;
  final ClipboardReader _read;
  final Clock _clock;

  String? _ignoredUrl;
  DateTime? _ignoredAt;

  /// Returns the first http(s) URL in the clipboard, or null when missing /
  /// suppressed by the cooldown window.
  Future<String?> peek() async {
    final text = await _read();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(r'https?://[^\s)\]"]+').firstMatch(text);
    final url = match?.group(0);
    if (url == null) return null;
    if (_ignoredUrl == url && _ignoredAt != null) {
      final elapsed = _clock().difference(_ignoredAt!);
      if (elapsed < ignoreCooldown) return null;
    }
    return url;
  }

  void markIgnored(String url) {
    _ignoredUrl = url;
    _ignoredAt = _clock();
  }
}
