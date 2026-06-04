import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/utils/page_transitions.dart';

void main() {
  testWidgets('fkRoute pushes and reveals the destination', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(fkRoute<void>(builder: (_) => const _DestPage())),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.byType(_DestPage), findsOneWidget);
  });

  testWidgets('fkRoute enables the iOS-style left-edge back gesture', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );

    Navigator.of(homeContext).push(
      fkRoute<void>(builder: (_) => const _DestPage()),
    );
    await tester.pumpAndSettle();

    final route = ModalRoute.of(tester.element(find.byType(_DestPage)))!;
    expect(route, isA<CupertinoRouteTransitionMixin>());
    expect((route as CupertinoRouteTransitionMixin).popGestureEnabled, isTrue);
  });

  testWidgets('dragging from the left edge pops back to the previous page', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );

    Navigator.of(homeContext).push(
      fkRoute<void>(builder: (_) => const _DestPage()),
    );
    await tester.pumpAndSettle();
    expect(find.byType(_DestPage), findsOneWidget);

    // Start at the left edge (x≈5) and drag past half the width, then release.
    final gesture = await tester.startGesture(const Offset(5, 200));
    await gesture.moveBy(const Offset(500, 0));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(find.byType(_DestPage), findsNothing);
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('reduce-motion degrades the transition to a plain fade', (
    tester,
  ) async {
    late BuildContext homeContext;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            homeContext = context;
            return const Scaffold(body: Text('home'));
          },
        ),
      ),
    );

    Navigator.of(homeContext).push(
      fkRoute<void>(builder: (_) => const _DestPage()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(CupertinoPageTransition), findsNothing);
  });
}

class _DestPage extends StatelessWidget {
  const _DestPage();
  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('dest'));
}
