import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/backup_service.dart';
import 'ai_settings_provider.dart';
import 'custom_recipe_provider.dart';
import 'inventory_provider.dart';
import 'shopping_provider.dart';
import 'storage_service_provider.dart';

/// Orchestrates backup export/import against the live, Drift-backed stores.
///
/// This is the ViewModel-level seam the Settings screen calls: it reads the
/// real source of truth on export and writes it back on import, leaving the
/// View to only map decode errors to dialogs and confirm the destructive
/// action. The pure (de)serialization lives in [BackupService].
class BackupController {
  BackupController(this._ref);

  final Ref _ref;

  /// Reads the live in-memory state (the source of truth, persisted to Drift)
  /// and serializes it to a JSON blob.
  String export() {
    final data = BackupData(
      inventory: _ref.read(inventoryProvider),
      addHistory: _ref.read(inventoryRepoProvider).loadHistory(),
      shopping: _ref.read(shoppingProvider),
      customRecipes: _ref.read(customRecipesProvider),
      aiSettings: _ref.read(aiSettingsProvider),
    );
    return BackupService.encode(data);
  }

  /// Restores [data] into the live stores, persisting to the active household
  /// scope and refreshing the UI.
  ///
  /// `replaceFromRemote` is the right restore primitive: it replaces a
  /// notifier's whole list and persists it locally with NO sync side effects
  /// (it is the same inbound path the sync engine uses). Add-history has no
  /// notifier method, so it is written through the repo and the derived
  /// provider is invalidated to re-derive from the fresh map.
  ///
  /// Every write passes `rethrowOnError: true` (and [saveHistory] throws on its
  /// own), so a failed persistence propagates out of [import] — the Settings
  /// screen surfaces it instead of falsely reporting a completed restore.
  /// Throws if any write fails.
  Future<void> import(BackupData data) async {
    await _ref
        .read(inventoryProvider.notifier)
        .replaceFromRemote(data.inventory, rethrowOnError: true);
    await _ref
        .read(shoppingProvider.notifier)
        .replaceFromRemote(data.shopping, rethrowOnError: true);
    await _ref
        .read(customRecipesProvider.notifier)
        .replaceFromRemote(data.customRecipes, rethrowOnError: true);

    await _ref.read(inventoryRepoProvider).saveHistory(data.addHistory);
    _ref.invalidate(addHistoryProvider);

    final aiSettings = data.aiSettings;
    if (aiSettings != null) {
      await _ref.read(aiSettingsProvider.notifier).save(aiSettings);
    }
  }
}

final backupControllerProvider = Provider<BackupController>(
  (ref) => BackupController(ref),
);
