import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

/// FreshKeeper 5 个底部 tab 的语义索引(与 `lib/app.dart` 的 `_screens` 列表
/// 顺序保持一致)。中间 `add` 是 primary FAB(设计稿 `ui.jsx::FKTabBar`)。
abstract final class FkTab {
  static const home = 0;
  static const fridge = 1;
  static const add = 2;
  static const recipes = 3;
  static const shopping = 4;
}

/// Currently selected tab index (0-4).
final navigationProvider = StateProvider<int>((ref) => FkTab.home);

/// Whether search overlay is active.
final searchActiveProvider = StateProvider<bool>((ref) => false);

/// Shopping category that should be expanded after navigation/search.
final shoppingCategoryToExpandProvider = StateProvider<String?>((ref) => null);

extension NavigationRef on WidgetRef {
  void navigateToTab(int index) {
    read(navigationProvider.notifier).state = index;
  }
}
