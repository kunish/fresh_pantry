import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('uses dark system chrome on light app surfaces', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    final regions = tester.widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byWidgetPredicate(
        (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
      ),
    );

    expect(regions, isNotEmpty);
    expect(regions.first.value.statusBarIconBrightness, Brightness.dark);
    expect(regions.first.value.statusBarBrightness, Brightness.light);
    expect(
      regions.first.value.systemNavigationBarIconBrightness,
      Brightness.dark,
    );
    expect(regions.first.value.systemNavigationBarColor, AppColors.surface);
  });
}
