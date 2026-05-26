import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/ai_draft_review_banner.dart';

void main() {
  testWidgets('shows review copy and action buttons', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiDraftReviewBanner(
            sourceUrl: 'https://www.xiachufang.com/recipe/1/',
            onRegenerate: () {},
            onDiscard: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('ai_draft_review_banner')), findsOneWidget);
    expect(find.text('✨ AI 草稿已填入，请核对下方字段'), findsOneWidget);
    expect(find.textContaining('来源:'), findsOneWidget);
    expect(find.byKey(const Key('ai_draft_review_regenerate')), findsOneWidget);
    expect(find.byKey(const Key('ai_draft_review_discard')), findsOneWidget);
  });
}
