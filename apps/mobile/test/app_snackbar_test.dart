import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/app_snackbar.dart';

void main() {
  testWidgets('showAppSnackBar renders floating SnackBar with the given text',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppSnackBar(context, '已保存'),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('已保存'), findsNothing);

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(find.text('已保存'), findsOneWidget);
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.behavior, SnackBarBehavior.floating);
  });

  testWidgets('showAppSnackBar wires actionLabel + onAction into SnackBarAction',
      (tester) async {
    var actionTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showAppSnackBar(
                  context,
                  '已删除',
                  actionLabel: '撤销',
                  onAction: () => actionTapped = true,
                ),
                child: const Text('show'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pumpAndSettle();

    expect(find.text('已删除'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);

    await tester.tap(find.widgetWithText(SnackBarAction, '撤销'));
    await tester.pump();
    expect(actionTapped, isTrue);
  });

  testWidgets('showAppSnackBar with neither actionLabel nor onAction renders no action',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showAppSnackBar(context, 'plain'),
              child: const Text('show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('show'));
    await tester.pump();

    expect(find.text('plain'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsNothing);
  });
}
