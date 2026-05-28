import 'package:flutter_riverpod/flutter_riverpod.dart';

mixin ReviewNotifierBase<TState> on Notifier<TState> {
  void clear();

  Future<T> applyAndClear<T>(Future<T> Function() apply) async {
    final result = await apply();
    clear();
    return result;
  }
}
