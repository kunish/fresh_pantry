import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provider for SharedPreferences instance.
///
/// This provider throws by default and must be overridden in
/// [ProviderScope] with a pre-initialized [SharedPreferences] instance
/// obtained in `main()`.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a real '
    'SharedPreferences instance via ProviderScope overrides.',
  );
});
