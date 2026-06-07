import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/food_log_entry.dart';
import 'package:fresh_pantry/utils/food_departure_sheet.dart';

class _Holder {
  FoodLogOutcome? value;
  bool done = false;
}

Future<_Holder> _open(WidgetTester tester, {String? itemName}) async {
  final holder = _Holder();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                holder.value = await showFoodDepartureOutcomeSheet(
                  context,
                  itemName: itemName,
                );
                holder.done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return holder;
}

void main() {
  testWidgets('tapping 吃完 returns consumed', (tester) async {
    final holder = await _open(tester, itemName: '番茄');
    expect(find.text('「番茄」要移除'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('departure-consumed')));
    await tester.pumpAndSettle();
    expect(holder.done, isTrue);
    expect(holder.value, FoodLogOutcome.consumed);
  });

  testWidgets('tapping 扔了 returns wasted', (tester) async {
    final holder = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('departure-wasted')));
    await tester.pumpAndSettle();
    expect(holder.value, FoodLogOutcome.wasted);
  });

  testWidgets('cancel returns null', (tester) async {
    final holder = await _open(tester);
    await tester.tap(find.byKey(const ValueKey('departure-cancel')));
    await tester.pumpAndSettle();
    expect(holder.done, isTrue);
    expect(holder.value, isNull);
  });
}
