import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';

void main() {
  testWidgets('App smoke test - renders without crashing', (
    WidgetTester tester,
  ) async {
    // Provide a mock SharedPreferences for the test environment
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify the app renders — the FreshPantryApp widget should exist
    expect(find.byType(FreshPantryApp), findsOneWidget);
  });
}
