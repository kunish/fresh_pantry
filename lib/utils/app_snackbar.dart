import 'package:flutter/material.dart';

/// 统一项目内的 SnackBar 调用。处理 `clearSnackBars`、浮动样式、12 圆角等共享配置。
///
/// `actionLabel` 与 `onAction` 必须同时提供或同时省略。`actionTextColor` 仅在
/// 提供 action 时有意义,用于匹配背景色对比的标签颜色(例如 onError / onPrimary)。
ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showAppSnackBar(
  BuildContext context,
  String message, {
  Color? backgroundColor,
  Duration duration = const Duration(seconds: 4),
  String? actionLabel,
  VoidCallback? onAction,
  Color? actionTextColor,
  bool clearPrevious = true,
  bool persist = false,
}) {
  assert(
    (actionLabel == null && onAction == null) ||
        (actionLabel != null && onAction != null),
    'actionLabel 与 onAction 必须同时提供或同时省略',
  );
  final messenger = ScaffoldMessenger.of(context);
  if (clearPrevious) {
    messenger.clearSnackBars();
  }
  return messenger.showSnackBar(
    SnackBar(
      content: Text(message),
      persist: persist,
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: duration,
      action: (actionLabel != null && onAction != null)
          ? SnackBarAction(
              label: actionLabel,
              textColor: actionTextColor,
              onPressed: onAction,
            )
          : null,
    ),
  );
}
