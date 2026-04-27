import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
}
