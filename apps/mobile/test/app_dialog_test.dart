import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/app_dialog.dart';

void main() {
  testWidgets('showAppConfirmDialog returns true when confirm tapped',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showAppConfirmDialog(
                    context,
                    title: '删除食材',
                    content: '确定要删除吗？',
                    confirmLabel: '删除',
                    isDestructive: true,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('删除食材'), findsOneWidget);
    expect(find.text('确定要删除吗？'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('showAppConfirmDialog returns false when cancel tapped',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAppConfirmDialog(
                  context,
                  title: '丢弃更改',
                  content: '确定要丢弃吗？',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('showAppConfirmDialog returns false when dismissed via barrier',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showAppConfirmDialog(
                  context,
                  title: 't',
                  content: 'c',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Dismiss the dialog by tapping the modal barrier.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });
}
