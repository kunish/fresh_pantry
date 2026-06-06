import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_details.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/food_details_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/ingredient_detail_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_database.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    '来源行在联网查询期间不谎报「本地食材知识库」，待结果到达再显示真实来源',
    (tester) async {
      final item = Ingredient(
        name: '牛奶',
        category: FoodCategories.dairyAndEggs,
        quantity: '1',
        unit: '盒',
        imageUrl: '',
        freshnessPercent: 1,
        state: FreshnessState.fresh,
        expiryLabel: '新鲜',
        storage: IconType.fridge,
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = newTestDatabase();
      addTearDown(db.close);

      final completer = Completer<FoodDetails?>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            ...testStorageOverrides(database: db),
            foodDetailsClientProvider.overrideWithValue(
              _DeferredFoodDetailsClient(completer.future),
            ),
          ],
          child: MaterialApp(home: IngredientDetailScreen(ingredient: item)),
        ),
      );
      await tester.pump();

      // 查询尚未返回:来源行不得谎报「本地食材知识库」(此刻还没查到来源)。
      expect(find.text('本地食材知识库'), findsNothing);
      expect(find.text('查询中…'), findsOneWidget);

      // 联网结果到达后显示真实来源,占位消失。
      completer.complete(
        FoodDetails(
          displayName: '牛奶',
          description: '乳品蛋类食材',
          imageUrl: null,
          category: FoodCategories.dairyAndEggs,
          storage: IconType.fridge,
          shelfLifeDays: 7,
          source: 'Open Food Facts',
          fetchedAt: DateTime.utc(2026, 5, 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('查询中…'), findsNothing);
      expect(find.text('Open Food Facts'), findsOneWidget);
    },
  );
}

class _DeferredFoodDetailsClient implements FoodDetailsClient {
  _DeferredFoodDetailsClient(this.result);

  final Future<FoodDetails?> result;

  @override
  Future<FoodDetails?> lookup(Ingredient ingredient) => result;
}
