import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// Currently selected tab index (0-3)
final navigationProvider = StateProvider<int>((ref) => 0);

/// Whether search overlay is active
final searchActiveProvider = StateProvider<bool>((ref) => false);

/// Shopping category that should be expanded after navigation/search.
final shoppingCategoryToExpandProvider = StateProvider<String?>((ref) => null);

extension NavigationRef on WidgetRef {
  void navigateToTab(int index) {
    read(navigationProvider.notifier).state = index;
  }
}
