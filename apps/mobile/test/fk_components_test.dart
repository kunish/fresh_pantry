import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/theme/app_theme.dart';
import 'package:fresh_pantry/widgets/shared/fk_card.dart';
import 'package:fresh_pantry/widgets/shared/fk_hero_header.dart';
import 'package:fresh_pantry/widgets/shared/fk_icon_button.dart';
import 'package:fresh_pantry/widgets/shared/fk_image_placeholder.dart';
import 'package:fresh_pantry/widgets/shared/fk_pill.dart';
import 'package:fresh_pantry/widgets/shared/fk_section_head.dart';
import 'package:fresh_pantry/widgets/shared/fk_status_badge.dart';
import 'package:fresh_pantry/widgets/shared/fk_top_bar.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: AppTheme.lightTheme, home: Scaffold(body: child));

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('FkCard renders child and supports onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        FkCard(
          onTap: () => taps++,
          child: const Text('hello'),
        ),
      ),
    );
    expect(find.text('hello'), findsOneWidget);
    await tester.tap(find.byType(FkCard));
    expect(taps, 1);
  });

  testWidgets('FkPill.status maps every FkStatus to the design label', (
    tester,
  ) async {
    for (final entry in kFkStatusStyles.entries) {
      await tester.pumpWidget(_wrap(FkPill.status(entry.key)));
      expect(find.text(entry.value.label), findsOneWidget);
    }
  });

  testWidgets('FkStatusBadge renders pill with status label', (tester) async {
    await tester.pumpWidget(_wrap(const FkStatusBadge(status: FkStatus.urgent)));
    expect(find.text('快过期'), findsOneWidget);
  });

  testWidgets('FkIconButton tap fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        FkIconButton(
          onTap: () => taps++,
          child: const Icon(Icons.add),
        ),
      ),
    );
    await tester.tap(find.byType(FkIconButton));
    expect(taps, 1);
  });

  testWidgets('FkTopBar shows title and subtitle and back', (tester) async {
    var backTaps = 0;
    await tester.pumpWidget(
      _wrap(
        FkTopBar(
          title: '我的食材',
          subtitle: '共 5 件',
          onBack: () => backTaps++,
        ),
      ),
    );
    expect(find.text('我的食材'), findsOneWidget);
    expect(find.text('共 5 件'), findsOneWidget);
    await tester.tap(find.byType(FkIconButton));
    expect(backTaps, 1);
  });

  testWidgets('FkSectionHead renders title + count + action with chevron', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        FkSectionHead(
          title: '该用了',
          count: 3,
          actionLabel: '全部',
          onAction: () => taps++,
        ),
      ),
    );
    expect(find.text('该用了'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    await tester.tap(find.text('全部'));
    expect(taps, 1);
  });

  testWidgets('FkHeroHeader paints gradient body with child', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FkHeroHeader(child: Text('hero', style: TextStyle(color: Colors.white))),
      ),
    );
    expect(find.text('hero'), findsOneWidget);
  });

  testWidgets('FkImagePlaceholder renders label', (tester) async {
    await tester.pumpWidget(
      _wrap(const FkImagePlaceholder(height: 80, label: 'dish')),
    );
    expect(find.text('dish'), findsOneWidget);
  });
}
