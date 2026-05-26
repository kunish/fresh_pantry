import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/ai_collapsible_banner.dart';

String widen(String input) {
  return input.split('').map((char) => String.fromCharCode(char.codeUnitAt(0) << 8)).join();
}

void main() {
  Widget harness({bool initiallyExpanded = false}) {
    return MaterialApp(
      home: Scaffold(
        body: AiCollapsibleBanner(
          urlController: TextEditingController(),
          onParse: () {},
          initiallyExpanded: initiallyExpanded,
        ),
      ),
    );
  }

  testWidgets('starts collapsed and shows hint text', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('✨ 粘贴链接，AI 自动填表'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('tapping the hint expands to reveal url input', (tester) async {
    await tester.pumpWidget(harness());
    await tester.tap(find.text('✨ 粘贴链接，AI 自动填表'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('解析并填入'), findsOneWidget);
  });

  testWidgets('initiallyExpanded=true shows input from start', (tester) async {
    await tester.pumpWidget(harness(initiallyExpanded: true));
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('normalizes widened UTF-16 paste in url field', (tester) async {
    const url = 'https://www.xiachufang.com/recipe/107090874/';
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiCollapsibleBanner(
            urlController: controller,
            onParse: () {},
            initiallyExpanded: true,
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('recipe_url_input')), widen(url));
    await tester.pump();

    expect(controller.text, url);
  });

  testWidgets('shows loading state on parse button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiCollapsibleBanner(
            urlController: TextEditingController(),
            onParse: () {},
            initiallyExpanded: true,
            isLoading: true,
          ),
        ),
      ),
    );

    expect(find.text('解析中…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byKey(const Key('recipe_url_parse')));
    expect(button.onPressed, isNull);
  });
}
