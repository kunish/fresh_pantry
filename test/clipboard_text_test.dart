import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/clipboard_text.dart';

String widen(String input) {
  return input.split('').map((char) => String.fromCharCode(char.codeUnitAt(0) << 8)).join();
}

void main() {
  group('normalizeClipboardText', () {
    test('returns supported URL unchanged', () {
      const url = 'https://www.xiachufang.com/recipe/107090874/';
      expect(normalizeClipboardText(url), url);
    });

    test('recovers widened UTF-16 ASCII paste', () {
      const url = 'https://www.xiachufang.com/recipe/107090874/';
      expect(normalizeClipboardText(widen(url)), url);
    });

    test('recovers null-interleaved UTF-16 paste', () {
      const url = 'https://www.xiachufang.com/recipe/107090874/';
      final interleaved = url.split('').expand((c) sync* {
        yield c;
        yield '\u0000';
      }).join();
      expect(normalizeClipboardText(interleaved), url);
    });

    test('extracts URL from surrounding text', () {
      const url = 'https://www.xiachufang.com/recipe/107090874/';
      expect(
        normalizeClipboardText('看看这个 $url 很赞'),
        url,
      );
    });

    test('ensureRecipeUrl adds https and repairs vw host', () {
      expect(
        ensureRecipeUrl('vw.xiachufang.com/recipe/107090874/'),
        'https://www.xiachufang.com/recipe/107090874/',
      );
    });
  });

  group('decodeWidenedUtf16Ascii', () {
    test('decodes Recipe mojibake prefix', () {
      expect(
        decodeWidenedUtf16Ascii('爀攀挀椀瀀攀'),
        'recipe',
      );
    });
  });
}
