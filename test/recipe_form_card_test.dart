import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/widgets/recipe_form/recipe_form_card.dart';

void main() {
  testWidgets('renders icon, title, and child content', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.restaurant_menu,
            title: '基础信息',
            child: Text('卡片内容'),
          ),
        ),
      ),
    );

    expect(find.text('基础信息'), findsOneWidget);
    expect(find.byIcon(Icons.restaurant_menu), findsOneWidget);
    expect(find.text('卡片内容'), findsOneWidget);
  });

  testWidgets('renders count chip when countLabel is provided', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.list,
            title: '食材',
            countLabel: '3 项',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.text('3 项'), findsOneWidget);
  });

  testWidgets('omits count chip when countLabel is null', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RecipeFormCard(
            icon: Icons.list,
            title: '基础信息',
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );

    expect(find.byType(Container), findsWidgets); // sanity
    expect(find.text('3 项'), findsNothing);
  });
}
