import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/widgets/dashboard/recent_addition_item.dart';
import 'package:fresh_pantry/widgets/shared/cat_icon.dart';

void main() {
  testWidgets(
    'recent additions show quantity with unit, added time, and the category icon',
    (tester) async {
      final addedAt = DateTime.now().subtract(const Duration(hours: 2));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecentAdditionItem(
              item: Ingredient(
                name: '牛肉',
                quantity: '1',
                unit: '个',
                imageUrl: 'https://example.com/beef.jpg',
                freshnessPercent: 0.9,
                state: FreshnessState.fresh,
                category: '肉类海鲜',
                storage: IconType.fridge,
                addedAt: addedAt,
              ),
            ),
          ),
        ),
      );

      expect(find.text('牛肉'), findsOneWidget);
      expect(find.text('1 个'), findsOneWidget);
      expect(find.text('2小时前添加'), findsOneWidget);
      // FK CatIcon (cartoon line SVG) replaced the old Material icon.
      expect(find.byType(CatIcon), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );
}
