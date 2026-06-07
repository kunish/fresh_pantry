import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/food_categories.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/screens/waste_insights_screen.dart';
import 'package:fresh_pantry/widgets/dashboard/waste_insights_card.dart';

import 'support/test_database.dart';

FoodLogEntry _entry({
  required String id,
  FoodLogOutcome outcome = FoodLogOutcome.consumed,
  bool wasExpiring = false,
}) => FoodLogEntry(
  id: id,
  name: '番茄',
  category: FoodCategories.freshProduce,
  outcome: outcome,
  loggedAt: DateTime.now(),
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
      child: const MaterialApp(home: Scaffold(body: WasteInsightsCard())),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('hidden when there is no data this month', (tester) async {
    await _pump(tester, const []);
    expect(find.byKey(const ValueKey('dash-waste-insights')), findsNothing);
    expect(find.text('减废成效'), findsNothing);
  });

  testWidgets('shows used/wasted counts and a rescued badge', (tester) async {
    await _pump(tester, [
      _entry(id: '1'),
      _entry(id: '2', wasExpiring: true), // consumed + expiring -> rescued
      _entry(id: '3', outcome: FoodLogOutcome.wasted),
    ]);
    expect(find.text('减废成效'), findsOneWidget);
    expect(find.text('本月用掉 2 · 浪费 1'), findsOneWidget);
    expect(find.text('抢救 1'), findsOneWidget);
  });

  testWidgets('zero-waste month reads as a positive line', (tester) async {
    await _pump(tester, [_entry(id: '1'), _entry(id: '2')]);
    expect(find.textContaining('零浪费'), findsOneWidget);
  });

  testWidgets('tap opens the insights screen', (tester) async {
    await _pump(tester, [_entry(id: '1', outcome: FoodLogOutcome.wasted)]);
    await tester.tap(find.byKey(const ValueKey('dash-waste-insights')));
    await tester.pumpAndSettle();
    expect(find.byType(WasteInsightsScreen), findsOneWidget);
  });
}
