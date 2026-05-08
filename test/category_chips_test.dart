import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:fresh_pantry/widgets/common/category_chips.dart';

void main() {
  testWidgets('keeps all category fixed while other categories scroll', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: CategoryChips(
              categories: const ['全部', '蔬菜', '水果', '肉类', '乳制品'],
              selectedCategory: '全部',
              onSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.ancestor(of: find.text('全部'), matching: find.byType(ListView)),
      findsNothing,
    );
    expect(
      find.ancestor(of: find.text('蔬菜'), matching: find.byType(ListView)),
      findsOneWidget,
    );
  });

  testWidgets('tapping a chip fires onSelected with the chip label', (
    tester,
  ) async {
    final selections = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: CategoryChips(
              categories: const ['全部', '蔬菜', '水果'],
              selectedCategory: '全部',
              onSelected: selections.add,
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('蔬菜'));
    await tester.pumpAndSettle();
    expect(selections, ['蔬菜']);

    await tester.tap(find.text('水果'));
    await tester.pumpAndSettle();
    expect(selections, ['蔬菜', '水果']);
  });

  testWidgets(
    'selected chip uses primary background, others use surfaceContainerHigh',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: CategoryChips(
                categories: const ['全部', '蔬菜', '水果'],
                selectedCategory: '蔬菜',
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Color colorOf(String label) {
        final container = tester.widget<AnimatedContainer>(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        final decoration = container.decoration as BoxDecoration;
        return decoration.color!;
      }

      expect(colorOf('蔬菜'), AppColors.primary);
      expect(colorOf('全部'), AppColors.surfaceContainerHigh);
      expect(colorOf('水果'), AppColors.surfaceContainerHigh);
    },
  );
}
