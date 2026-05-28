import 'dart:async';
import 'package:flutter/foundation.dart';

/// 串行化持久化写入的 mixin。
/// 每个 Notifier 把一次写入操作传入 [queuePersistence]，队列内部确保前一个完成后再开始下一个，
/// 单个写入失败不会卡住后续（失败仅在 debug 中打印，不传播）。
mixin PersistenceQueue {
  Future<void> _pendingPersistence = Future.value();

  /// 把一次写入串到队列尾。返回的 Future 在该次写入完成后 resolve。
  ///
  /// 内部队列始终吞掉异常（仅 [debugPrint]），避免一次写失败卡住后续写。
  /// 当 [rethrowError] 为 true 时，返回的 Future 透传该次写入的真实结果（含异常），
  /// 使调用方能感知失败（例如 Review 在持久化失败时保留草稿并提示重试），
  /// 同时不影响内部队列继续运行。
  @protected
  Future<void> queuePersistence(
    Future<void> Function() write, {
    bool rethrowError = false,
  }) {
    final result = _pendingPersistence.then((_) => write());
    _pendingPersistence = result.catchError((Object e, StackTrace st) {
      debugPrint('PersistenceQueue write failed: $e');
    });
    return rethrowError ? result : _pendingPersistence;
  }
}
