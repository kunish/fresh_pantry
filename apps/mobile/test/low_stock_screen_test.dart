import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/low_stock_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _entry(int count) => {
  'count': count,
  'category': FoodCategories.other,
  'storage': 'fridge',
  'unit': '个',
};

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({
    'add_history': jsonEncode({'鸡蛋': _entry(5), '牛奶': _entry(4)}),
  });
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        inventorySeedProvider.overrideWithValue(const []),
      ],
      child: const MaterialApp(home: LowStockScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists frequent items with all selected by default', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('鸡蛋'), findsOneWidget);
    expect(find.text('牛奶'), findsOneWidget);
    // 两项默认全选 → CTA 计数为 2。
    expect(find.text('一键加入购物清单 (2)'), findsOneWidget);
  });

  testWidgets('toggling a row updates the selected count', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('鸡蛋'));
    await tester.pumpAndSettle();

    expect(find.text('一键加入购物清单 (1)'), findsOneWidget);
  });
}
