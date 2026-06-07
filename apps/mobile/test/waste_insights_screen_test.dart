import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/waste_insights_screen.dart';

import 'support/test_database.dart';

FoodLogEntry _entry({
  required String id,
  FoodLogOutcome outcome = FoodLogOutcome.consumed,
  bool wasExpiring = false,
  String category = FoodCategories.freshProduce,
  DateTime? loggedAt,
}) => FoodLogEntry(
  id: id,
  name: '某物',
  category: category,
  outcome: outcome,
  loggedAt: loggedAt ?? DateTime.now(),
  wasExpiring: wasExpiring,
);

Future<void> _pump(WidgetTester tester, List<FoodLogEntry> entries) async {
  final db = newTestDatabase();
  addTearDown(db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        foodLogSeedProvider.overrideWithValue(entries),
      ],
      child: const MaterialApp(home: WasteInsightsScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty state invites the user to start tracking', (tester) async {
    await _pump(tester, const []);
    expect(find.text('本月还没有减废记录'), findsOneWidget);
  });

  testWidgets('shows used rate, metrics, and most-wasted categories', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(id: '1'),
      _entry(id: '2'),
      _entry(id: '3', wasExpiring: true), // rescued
      _entry(
        id: '4',
        outcome: FoodLogOutcome.wasted,
        category: FoodCategories.dairyAndEggs,
      ),
    ]);

    // 3 consumed / 4 total -> 75% used rate.
    expect(find.text('75%'), findsOneWidget);
    expect(find.text('本月共处理 4 样食材'), findsOneWidget);
    // Metric tiles.
    expect(find.text('用掉'), findsOneWidget);
    expect(find.text('浪费'), findsOneWidget);
    expect(find.text('抢救临期'), findsOneWidget);
    // Wasted-by-category breakdown.
    expect(find.text('最常浪费'), findsOneWidget);
    expect(find.text(FoodCategories.dairyAndEggs), findsOneWidget);
    expect(find.text('1 样'), findsWidgets);
  });

  testWidgets('switching to 近 90 天 widens the window and updates the copy', (
    tester,
  ) async {
    await _pump(tester, [
      _entry(id: 'recent'),
      // 40 days ago: before this month's start, inside the 90-day window.
      _entry(id: 'old', loggedAt: DateTime.now().subtract(const Duration(days: 40))),
    ]);

    // 本月 default counts only the recent entry.
    expect(find.text('本月共处理 1 样食材'), findsOneWidget);

    await tester.tap(find.text('近 90 天'));
    await tester.pumpAndSettle();

    expect(find.text('近 90 天用掉率'), findsOneWidget);
    expect(find.text('近 90 天共处理 2 样食材'), findsOneWidget);
  });
}
