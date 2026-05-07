import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/ai_settings.dart';
import 'storage_service_provider.dart';

const aiSettingsStorageKey = 'ai_settings_v1';

class AiSettingsNotifier extends Notifier<AiSettings> {
  late SharedPreferences _prefs;

  @override
  AiSettings build() {
    _prefs = ref.read(sharedPreferencesProvider);
    final raw = _prefs.getString(aiSettingsStorageKey);
    if (raw == null || raw.isEmpty) return AiSettings.empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return AiSettings.fromJson(map);
    } catch (_) {
      return AiSettings.empty;
    }
  }

  Future<void> save(AiSettings next) async {
    final ok = await _prefs.setString(
      aiSettingsStorageKey,
      jsonEncode(next.toJson()),
    );
    if (!ok) {
      throw StateError('Failed to save AiSettings');
    }
    state = next;
  }
}

final aiSettingsProvider =
    NotifierProvider<AiSettingsNotifier, AiSettings>(AiSettingsNotifier.new);
