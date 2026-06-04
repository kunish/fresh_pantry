import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/ai_settings.dart';
import '../services/ai_client.dart';
import '../storage/ai_settings_repo.dart';
import 'storage_service_provider.dart';

const aiSettingsStorageKey = AiSettingsRepo.storageKey;

/// A chat call bound to the saved AI settings.
typedef AiChat =
    Future<String> Function(
      List<AiMessage> messages, {
      Map<String, dynamic>? responseFormat,
    });

/// Injectable AI chat seam bound to the saved [aiSettingsProvider].
///
/// Parser flows (ingredient / recipe) read this instead of calling the static
/// [AiClient.chat] inline, so there is one provider to override in tests rather
/// than a hard-coded static per screen. The AI-settings *test-connection* probe
/// intentionally does NOT use this — it must exercise the in-progress edited
/// settings the user is typing, not the persisted ones.
final aiChatProvider = Provider<AiChat>((ref) {
  return (messages, {responseFormat}) => AiClient.chat(
    settings: ref.read(aiSettingsProvider),
    messages: messages,
    responseFormat: responseFormat,
  );
});

class AiSettingsNotifier extends Notifier<AiSettings> {
  late AiSettingsRepo _repo;

  @override
  AiSettings build() {
    _repo = ref.read(aiSettingsRepoProvider);
    return _repo.load();
  }

  Future<void> save(AiSettings next) async {
    _repo.save(next);
    state = next;
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
