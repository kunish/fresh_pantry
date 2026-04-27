import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localized app display name', () {
    test('Android launcher label comes from localized string resources', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();

      expect(manifest, contains('android:label="@string/app_name"'));

      _expectFileContains(
        'android/app/src/main/res/values/strings.xml',
        '<string name="app_name">Fresh Pantry</string>',
      );
      _expectFileContains(
        'android/app/src/main/res/values-zh/strings.xml',
        '<string name="app_name">食材管家</string>',
      );
    });

    test('iOS bundle name is localized for English and Simplified Chinese', () {
      _expectFileContains(
        'ios/Runner/en.lproj/InfoPlist.strings',
        'CFBundleDisplayName = "Fresh Pantry";',
      );
      _expectFileContains(
        'ios/Runner/zh-Hans.lproj/InfoPlist.strings',
        'CFBundleDisplayName = "食材管家";',
      );
      _expectFileContains(
        'ios/Runner.xcodeproj/project.pbxproj',
        'InfoPlist.strings in Resources',
      );
      _expectFileContains('ios/Runner.xcodeproj/project.pbxproj', 'zh-Hans');
    });

    test(
      'macOS bundle name is localized for English and Simplified Chinese',
      () {
        _expectFileContains(
          'macos/Runner/en.lproj/InfoPlist.strings',
          'CFBundleDisplayName = "Fresh Pantry";',
        );
        _expectFileContains(
          'macos/Runner/zh-Hans.lproj/InfoPlist.strings',
          'CFBundleDisplayName = "食材管家";',
        );
        _expectFileContains(
          'macos/Runner.xcodeproj/project.pbxproj',
          'InfoPlist.strings in Resources',
        );
        _expectFileContains(
          'macos/Runner.xcodeproj/project.pbxproj',
          'zh-Hans',
        );
      },
    );

    test('Flutter app title is generated from the system locale', () {
      final app = File('lib/app.dart').readAsStringSync();

      expect(app, contains('onGenerateTitle:'));
      expect(app, isNot(contains("locale: const Locale('zh', 'CN')")));
    });
  });
}

void _expectFileContains(String path, String expectedContent) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: '$path should exist');
  expect(file.readAsStringSync(), contains(expectedContent));
}
