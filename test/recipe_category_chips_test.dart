import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/recipe_category_chips.dart';

void main() {
  Widget harness({
    required String selected,
    required ValueChanged<String> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: RecipeCategoryChips(
            selected: selected,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('renders preset categories and "+ 其他"', (tester) async {
    await tester.pumpWidget(harness(selected: '家常', onChanged: (_) {}));
    for (final c in ['家常', '川菜', '粤菜']) {
      expect(find.text(c), findsOneWidget);
    }
    expect(find.text('+ 其他'), findsOneWidget);
  });

  testWidgets('selecting a preset chip emits onChanged', (tester) async {
    final emitted = <String>[];
    await tester
        .pumpWidget(harness(selected: '家常', onChanged: emitted.add));
    await tester.tap(find.text('川菜'));
    await tester.pumpAndSettle();
    expect(emitted, ['川菜']);
  });

  testWidgets('non-preset selected value is rendered as a selected chip',
      (tester) async {
    await tester
        .pumpWidget(harness(selected: '日料', onChanged: (_) {}));
    expect(find.text('日料'), findsOneWidget);
  });

  testWidgets('tapping "+ 其他" opens dialog and emits typed value',
      (tester) async {
    final emitted = <String>[];
    await tester
        .pumpWidget(harness(selected: '家常', onChanged: emitted.add));

    await tester.tap(find.text('+ 其他'));
    await tester.pumpAndSettle();

    expect(find.text('自定义分类'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '日料');
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(emitted, ['日料']);
  });
}
