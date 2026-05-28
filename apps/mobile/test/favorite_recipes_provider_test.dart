import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/providers/favorite_recipes_provider.dart';
import 'package:fresh_pantry/providers/storage_service_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _buildContainer({
  Map<String, Object> initial = const {},
}) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
}

void main() {
  group('favoriteRecipesProvider', () {
    test('starts empty when nothing is saved', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);
      expect(container.read(favoriteRecipesProvider), isEmpty);
    });

    test('hydrates from stored ids on build', () async {
      final container = await _buildContainer(
        initial: {favoriteRecipesStorageKey: '["r1","r2"]'},
      );
      addTearDown(container.dispose);
      expect(container.read(favoriteRecipesProvider), {'r1', 'r2'});
    });

    test('toggle adds then removes, and isFavorite reflects state', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);
      final notifier = container.read(favoriteRecipesProvider.notifier);

      expect(notifier.isFavorite('r1'), isFalse);

      await notifier.toggle('r1');
      expect(notifier.isFavorite('r1'), isTrue);
      expect(container.read(favoriteRecipesProvider), {'r1'});
      expect(container.read(isRecipeFavoriteProvider('r1')), isTrue);

      await notifier.toggle('r1');
      expect(notifier.isFavorite('r1'), isFalse);
      expect(container.read(favoriteRecipesProvider), isEmpty);
      expect(container.read(isRecipeFavoriteProvider('r1')), isFalse);
    });

    test('toggle ignores an empty recipe id', () async {
      final container = await _buildContainer();
      addTearDown(container.dispose);

      await container.read(favoriteRecipesProvider.notifier).toggle('');

      expect(container.read(favoriteRecipesProvider), isEmpty);
    });

    test('toggled favorites persist across a fresh container', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final c1 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      await c1.read(favoriteRecipesProvider.notifier).toggle('r1');
      await c1.read(favoriteRecipesProvider.notifier).toggle('r2');
      c1.dispose();

      final c2 = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(c2.dispose);
      expect(c2.read(favoriteRecipesProvider), {'r1', 'r2'});
    });
  });
}
