import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ingredient.dart';
import 'package:fresh_pantry/models/storage_area.dart';
import 'package:fresh_pantry/providers/inventory_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/add_ingredient_screen.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('add ingredient save shows missing field prompt', (tester) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': '[]',
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: AddIngredientScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('保存前请补充：食材名称'), findsOneWidget);
    expect(container.read(inventoryProvider), isEmpty);
  });

  testWidgets('add undo removes the added item even after list changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'inventory_items': jsonEncode([_ingredient('旧食材').toJson()]),
      'shopping_items': '[]',
      'add_history': '{}',
    });
    final prefs = await SharedPreferences.getInstance();
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: Builder(
          builder: (context) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(body: AddIngredientScreen()),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '临时食材');
    await tester.ensureVisible(find.text('保存'));
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    await container.read(inventoryProvider.notifier).remove(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(container.read(inventoryProvider), isEmpty);
  });
}

Ingredient _ingredient(String name) {
  return Ingredient(
    name: name,
    quantity: '1',
    unit: '份',
    imageUrl: '',
    freshnessPercent: 1,
    state: FreshnessState.fresh,
    category: '测试',
    storage: IconType.fridge,
    expiryLabel: '新鲜',
  );
}
