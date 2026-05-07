import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:fresh_pantry/widgets/shared/pill_chip.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  Container findChipContainer(WidgetTester tester) {
    return tester.widget<Container>(
      find.descendant(
        of: find.byType(PillChip),
        matching: find.byType(Container),
      ),
    );
  }

  testWidgets('PillChip renders label without an icon by default',
      (tester) async {
    await tester.pumpWidget(wrap(const PillChip(label: 'pillchip')));

    expect(find.text('pillchip'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('PillChip renders the leading icon when provided',
      (tester) async {
    await tester.pumpWidget(wrap(
      const PillChip(label: '20分钟', icon: Icons.timer_outlined),
    ));

    expect(find.text('20分钟'), findsOneWidget);
    expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
  });

  testWidgets('PillChip selected state uses primary background',
      (tester) async {
    await tester.pumpWidget(
      wrap(const PillChip(label: 'sel', selected: true)),
    );
    final selectedDecoration =
        findChipContainer(tester).decoration as BoxDecoration;
    expect(selectedDecoration.color, AppColors.primary);

    await tester.pumpWidget(
      wrap(const PillChip(label: 'sel', selected: false)),
    );
    final unselectedDecoration =
        findChipContainer(tester).decoration as BoxDecoration;
    expect(unselectedDecoration.color, AppColors.surfaceContainerLow);
    expect(unselectedDecoration.color, isNot(AppColors.primary));
  });

  testWidgets('PillChip onTap callback fires when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(PillChip(label: 'tap', onTap: () => taps++)),
    );

    await tester.tap(find.byType(PillChip));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('PillChip with borderColor draws a border', (tester) async {
    await tester.pumpWidget(wrap(
      const PillChip(label: 'border', borderColor: AppColors.primary),
    ));

    final decoration = findChipContainer(tester).decoration as BoxDecoration;
    expect(decoration.border, isNotNull);
    expect(decoration.border!.top.color, AppColors.primary);
  });
}
