import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/widgets/shared/ai_draft_field.dart';

void main() {
  testWidgets('renders AI badge when source is ai', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AiDraftFieldChip<String>(
          label: '名称',
          field: DraftField.ai('番茄'),
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.text('AI 填'), findsOneWidget);
    expect(find.text('番茄'), findsOneWidget);
  });

  testWidgets('hides AI badge after edit (source becomes user)', (tester) async {
    DraftField<String> current = DraftField.ai('番茄');
    await tester.pumpWidget(StatefulBuilder(
      builder: (context, setState) => MaterialApp(
        home: Scaffold(
          body: AiDraftFieldChip<String>(
            label: '名称',
            field: current,
            onChanged: (next) => setState(() => current = next),
            editorBuilder: (initial, save) => TextButton(
              key: const Key('apply_user_edit'),
              onPressed: () => save('西红柿'),
              child: const Text('apply'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('番茄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apply_user_edit')));
    await tester.pumpAndSettle();
    expect(find.text('西红柿'), findsOneWidget);
    expect(find.text('AI 填'), findsNothing);
  });
}
