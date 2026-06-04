import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// 全 App 统一的页面路由 —— iOS 横向滑动转场,自带左边缘「跟手左滑返回」手势。
///
/// 替代裸 [MaterialPageRoute],让全 App 导航既有一致的转场,又能在任意页面从
/// 左边缘左滑返回。基于 [CupertinoPageRoute] 复用框架久经考验的边缘返回手势,
/// 不分平台(Android 同样可左滑返回)。
///
/// 尊重「减弱动态效果」:[MediaQuery.disableAnimationsOf] 为真时转场退化为纯
/// 淡入(无横滑位移,也不挂载跟手手势),与系统无障碍一致。
Route<T> fkRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  return _FkPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}

/// [CupertinoPageRoute] 的薄封装:仅在 reduce-motion 时把横滑转场换成淡入,
/// 其余行为(横滑动画 + 左边缘返回手势)完全沿用 Cupertino 实现。
class _FkPageRoute<T> extends CupertinoPageRoute<T> {
  _FkPageRoute({
    required super.builder,
    super.settings,
    super.fullscreenDialog,
  });

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return FadeTransition(opacity: animation, child: child);
    }
    return super.buildTransitions(
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
