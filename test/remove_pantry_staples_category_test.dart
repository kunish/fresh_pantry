import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_knowledge.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  test('former pantry staple defaults no longer use the removed category', () {
    final defaults = FoodKnowledge.lookup('大米');

    expect(defaults, isNotNull);
    expect(defaults!.category, '其他');
    expect(defaults.storage, IconType.pantry);
  });

  test(
    'legacy pantry staple categories are exposed as other in inventory',
    () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': jsonEncode([
          _ingredient(name: '大米', category: '食品柜常备').toJson(),
        ]),
        'add_history': '{}',
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(container.read(categoriesProvider), isNot(contains('食品柜常备')));
      expect(container.read(categoriesProvider), contains('其他'));

      container.read(selectedCategoryProvider.notifier).state = '其他';

      expect(
        container.read(filteredByCategoryProvider).map((item) => item.name),
        ['大米'],
      );
    },
  );

  test(
    'legacy pantry staple add history is normalized for frequent items',
    () async {
      SharedPreferences.setMockInitialValues({
        'inventory_items': '[]',
        'add_history': jsonEncode({
          '大米': {
            'count': 2,
            'category': '食品柜常备',
            'storage': 'pantry',
            'unit': '袋',
          },
        }),
      });
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final frequentItem = container.read(frequentItemsProvider).single;

      expect(frequentItem.name, '大米');
      expect(frequentItem.category, '其他');
    },
  );

  testWidgets('add ingredient category picker omits pantry staples', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: AddIngredientScreen())),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text('食品柜常备'), findsNothing);
    expect(find.text('其他'), findsOneWidget);
  });
}

Ingredient _ingredient({required String name, required String category}) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '袋',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: category,
    storage: IconType.pantry,
    expiryLabel: '新鲜',
  );
}
