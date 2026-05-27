/// 项目间距 token。直接以 px 命名,避免歧义;实际 px 与 logical px 在 Flutter 中等价。
class AppSpacing {
  AppSpacing._();

  static const double xs = 4; // 紧凑间距
  static const double sm = 8; // 元素内部
  static const double md = 12; // 元素之间
  static const double lg = 16; // 章节内段间
  static const double xl = 20; // 章节边距
  static const double xxl = 24; // 屏幕级页边距 (常用)
  static const double xxxl = 28;
  static const double huge = 32;
}
