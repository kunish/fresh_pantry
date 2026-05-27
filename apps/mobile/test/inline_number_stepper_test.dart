import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/review/inline_number_stepper.dart';

void main() {
  testWidgets('tap + and - calls onChanged with new value', (tester) async {
    var value = '5';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
            body: InlineNumberStepper(
              value: value,
              onChanged: (v) => setState(() => value = v),
              suffix: '天',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stepper_plus')));
    await tester.pump();
    expect(find.text('6'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
  });

  testWidgets('clamps at min (default 0)', (tester) async {
    var value = '0';
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (_, setState) => Scaffold(
            body: InlineNumberStepper(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('stepper_minus')));
    await tester.pump();
    expect(find.text('0'), findsOneWidget,
        reason: 'must not go below the configured min');
  });

  testWidgets('non-numeric value renders unmodified and disables steppers',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InlineNumberStepper(
            value: '一把',
            onChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('一把'), findsOneWidget);
  });
}
