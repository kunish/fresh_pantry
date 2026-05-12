import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fresh_pantry/app.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:fresh_pantry/services/share_intent_service.dart';
import 'package:fresh_pantry/widgets/common/bottom_nav_bar.dart';

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('App smoke test renders dashboard chrome', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          systemShareSourceProvider.overrideWithValue(InMemoryShareSource()),
        ],
        child: const FreshPantryApp(),
      ),
    );
    await tester.pumpAndSettle();

    // Bottom navigation chrome must be present on the home shell.
    expect(find.byType(BottomNavBar), findsOneWidget);
    // FK redesign hero: total inventory stat label appears.
    expect(find.text('你的冰箱状态'), findsOneWidget);
    // 5-tab nav shows the four labelled tabs (middle is a label-less FAB).
    for (final label in const ['首页', '食材', '菜谱', '清单']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
