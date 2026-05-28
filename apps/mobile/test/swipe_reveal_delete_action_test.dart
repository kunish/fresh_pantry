import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/common/swipe_reveal_delete_action.dart';

void main() {
  testWidgets('reveals delete action and invokes callback after a left swipe', (
    tester,
  ) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
          body: SwipeRevealDeleteAction(
            deleteButtonKey: const Key('delete_action'),
            onDelete: () => deleted = true,
            child: const SizedBox(height: 72, child: Center(child: Text('苹果'))),
          ),
        ),
      ),
    );

    await tester.drag(find.text('苹果'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete_action')));

    expect(deleted, isTrue);
  });

  testWidgets('delete panel stays mounted during close animation', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: false),
        home: Scaffold(
          body: SwipeRevealDeleteAction(
            deleteButtonKey: const Key('swipe_delete_button'),
            onDelete: () {},
            child: const SizedBox(height: 72, child: Center(child: Text('橙子'))),
          ),
        ),
      ),
    );

    // Open the panel fully.
    await tester.drag(find.text('橙子'), const Offset(-100, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('delete_panel')), findsOneWidget);

    // Partially swipe back so drag-end snaps the remaining distance closed with
    // an animation (offset is still < 0 at release). Pump one frame mid-animation
    // — the panel must stay mounted (not flash away) until onEnd fires.
    await tester.drag(find.text('橙子'), const Offset(54, 0));
    await tester.pump();
    expect(find.byKey(const Key('delete_panel')), findsOneWidget);

    await tester.pumpAndSettle();
    // After animation completes the panel is gone.
    expect(find.byKey(const Key('delete_panel')), findsNothing);
  });
}
