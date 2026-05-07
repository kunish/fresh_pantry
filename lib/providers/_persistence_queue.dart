import 'dart:async';
import 'package:flutter/foundation.dart';

/// 串行化持久化写入的 mixin。
/// 每个 Notifier 把一次写入操作传入 [queuePersistence]，队列内部确保前一个完成后再开始下一个，
/// 单个写入失败不会卡住后续（失败仅在 debug 中打印，不传播）。
mixin PersistenceQueue {
  Future<void> _pendingPersistence = Future.value();

  /// 把一次写入串到队列尾。返回的 Future 在该次写入完成后 resolve。
  /// 异常会被 [debugPrint] 但不会 rethrow，避免一次写失败阻塞后续写。
  @protected
  Future<void> queuePersistence(Future<void> Function() write) {
    final next = _pendingPersistence
        .then((_) => write())
        .catchError((Object e, StackTrace st) {
          debugPrint('PersistenceQueue write failed: $e');
        });
    _pendingPersistence = next;
    return next;
  }
}
