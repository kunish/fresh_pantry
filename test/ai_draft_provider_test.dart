import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_pantry/models/draft_field.dart';
import 'package:fresh_pantry/models/recipe_draft.dart';
import 'package:fresh_pantry/providers/ai_draft_provider.dart';

RecipeDraft _stubRecipeDraft(String url) => RecipeDraft(
      sourceUrl: url,
      name: DraftField.ai('Test'),
      category: DraftField.ai('家常'),
      cookingMinutes: DraftField.ai(30),
      difficulty: DraftField.ai(2),
      description: DraftField.ai(''),
      imageUrl: const DraftField(value: null, source: DraftSource.ai),
      ingredients: const [],
      steps: const [],
    );

void main() {
  test('starts as idle', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });

  test('runRecipeFromUrl sets running then complete on success', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final notifier = container.read(aiDraftProvider.notifier);
    final future = notifier.runRecipeFromUrl(
      'https://x',
      parser: (url) async => _stubRecipeDraft(url),
    );
    expect(container.read(aiDraftProvider).isRunning, true);
    await future;
    final state = container.read(aiDraftProvider);
    expect(state.isRunning, false);
    expect(state.recipeDraft?.sourceUrl, 'https://x');
  });

  test('runRecipeFromUrl sets error on parser exception', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(aiDraftProvider.notifier).runRecipeFromUrl(
          'https://x',
          parser: (_) async => throw Exception('boom'),
        );
    final state = container.read(aiDraftProvider);
    expect(state.error, isNotNull);
  });

  test('clear resets to idle', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final n = container.read(aiDraftProvider.notifier);
    await n.runRecipeFromUrl('https://x', parser: (u) async => _stubRecipeDraft(u));
    n.clear();
    expect(container.read(aiDraftProvider), const AiDraftState.idle());
  });
}
