import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/ai_settings.dart';
import 'package:fresh_pantry/providers/ai_settings_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _buildContainer({Map<String, Object> initial = const {}}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  return container;
}

void main() {
  group('aiSettingsProvider', () {
    test('returns AiSettings.empty when nothing saved', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);
      expect(container.read(aiSettingsProvider), AiSettings.empty);
    });

    test('save persists settings and updates state', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      const next = AiSettings(baseUrl: 'https://x/v1', apiKey: 'k', model: 'gpt-4o');
      await container.read(aiSettingsProvider.notifier).save(next);

      expect(container.read(aiSettingsProvider), next);
    });

    test('state survives a fresh container with same prefs', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      const next = AiSettings(baseUrl: 'https://x/v1', apiKey: 'k', model: 'gpt-4o');
      await c1.read(aiSettingsProvider.notifier).save(next);
      c1.dispose();

      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(aiSettingsProvider), next);
    });
  });
}
