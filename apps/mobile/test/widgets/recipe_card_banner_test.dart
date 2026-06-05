import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/recipe.dart';
import 'package:fresh_pantry/widgets/recipe_card.dart';
import 'package:fresh_pantry/widgets/shared/recipe_image.dart';

Recipe _recipe({String? imageUrl}) => Recipe(
  id: 'r1',
  name: '烙饼',
  category: '主食',
  difficulty: 4,
  cookingMinutes: 60,
  description: '',
  ingredients: const [],
  steps: const [],
  imageUrl: imageUrl,
);

void main() {
  testWidgets('banner 布局:模糊铺底 + 前景完整图,标题与 Hero 都在', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCard(
            recipe: _recipe(imageUrl: 'assets/recipes/images/x.jpg'),
            layout: RecipeCardLayout.banner,
            heroTag: 'recipe-image-r1',
          ),
        ),
      ),
    );

    expect(find.text('烙饼'), findsOneWidget);
    // 背景模糊铺底 + 前景 contain,两层都用 RecipeImage 喂同一张图。
    expect(find.byType(RecipeImage), findsNWidgets(2));
    // 模糊铺底用 ImageFiltered 包裹,保证任意比例的图都能填满 16:9 且不裁切。
    expect(find.byType(ImageFiltered), findsOneWidget);
    final hero = tester.widget<Hero>(find.byType(Hero));
    expect(hero.tag, 'recipe-image-r1');
  });

  testWidgets('横向布局:有图时走模糊铺底 + 完整图(不 cover 裁切)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCard(
            recipe: _recipe(imageUrl: 'assets/recipes/images/x.jpg'),
            // 默认 RecipeCardLayout.horizontal
          ),
        ),
      ),
    );

    expect(find.text('烙饼'), findsOneWidget);
    expect(find.byType(RecipeImage), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);
    // 前景用 contain 完整展示,绝不出现 cover 裁切。
    final fits = tester
        .widgetList<RecipeImage>(find.byType(RecipeImage))
        .map((w) => w.fit)
        .toSet();
    expect(fits.contains(BoxFit.contain), isTrue);
    expect(fits.contains(BoxFit.cover), isTrue); // 仅模糊铺底用 cover
  });

  testWidgets('banner 布局:空图回落到占位图标且不抛异常', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeCard(
            recipe: _recipe(imageUrl: ''),
            layout: RecipeCardLayout.banner,
          ),
        ),
      ),
    );

    expect(find.text('烙饼'), findsOneWidget);
    // 空图回落到按菜式分类着色的占位:主食 → 饭碗图标。
    expect(find.byIcon(Icons.rice_bowl_rounded), findsOneWidget);
    expect(find.byType(RecipeImage), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
