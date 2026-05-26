import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/services/recipe_page_fetcher.dart';

void main() {
  group('extractRecipePageText', () {
    test('pulls title, description, and visible text from HTML', () {
      const html = '''
<html>
<head>
<title>番茄炒蛋</title>
<meta name="description" content="家常快手菜" />
</head>
<body>
<script>var x = 1;</script>
<p>鸡蛋 2 个</p>
<p>西红柿 1 个</p>
</body>
</html>
''';

      final text = extractRecipePageText(html);
      expect(text, contains('标题: 番茄炒蛋'));
      expect(text, contains('摘要: 家常快手菜'));
      expect(text, contains('鸡蛋 2 个'));
      expect(text, isNot(contains('var x')));
    });
  });
}
