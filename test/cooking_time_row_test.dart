import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/cooking_time_row.dart';

void main() {
  Widget _harness({required CookingTimeRow row}) {
    return MaterialApp(home: Scaffold(body: row));
  }

  testWidgets('renders 6 chips with last labeled "120+"', (tester) async {
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(
        controller: TextEditingController(),
        onChanged: (_) {},
      ),
    ));
    for (final n in ['15', '30', '45', '60', '90']) {
      expect(find.text(n), findsOneWidget);
    }
    expect(find.text('120+'), findsOneWidget);
  });

  testWidgets('tapping chip writes value to controller and emits onChanged',
      (tester) async {
    final controller = TextEditingController();
    final emitted = <int?>[];
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: emitted.add),
    ));

    await tester.tap(find.text('45'));
    await tester.pumpAndSettle();
    expect(controller.text, '45');
    expect(emitted, [45]);
  });

  testWidgets('tapping "120+" chip writes 120', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: (_) {}),
    ));
    await tester.tap(find.text('120+'));
    await tester.pumpAndSettle();
    expect(controller.text, '120');
  });

  testWidgets('typing custom number does not crash and updates controller',
      (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: (_) {}),
    ));
    await tester.enterText(find.byType(TextField), '25');
    expect(controller.text, '25');
  });

  testWidgets('initial controller value populates the TextField (edit mode)',
      (tester) async {
    final controller = TextEditingController(text: '25');
    await tester.pumpWidget(_harness(
      row: CookingTimeRow(controller: controller, onChanged: (_) {}),
    ));
    // The TextField (an EditableText) should show '25' even though 25 is not a
    // preset chip value.
    expect(
      find.descendant(
        of: find.byType(TextField),
        matching: find.text('25'),
      ),
      findsOneWidget,
    );
  });
}
