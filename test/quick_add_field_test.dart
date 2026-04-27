import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/data/mock_data.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/widgets/shopping/quick_add_field.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('quick add field hides suggestion chips below the input', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'shopping_items': '[]'});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(home: Scaffold(body: QuickAddField())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('添加食材到清单...'), findsOneWidget);
    for (final suggestion in MockData.quickSuggestions) {
      expect(find.text('+ $suggestion'), findsNothing);
    }
  });
}
