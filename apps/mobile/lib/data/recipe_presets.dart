// lib/data/recipe_presets.dart

/// 食谱表单中常用的预设值。后续可能改为运行时可配置；本期为静态常量。
class RecipePresets {
  RecipePresets._();

  /// 分类预设。"+ 其他" 由 wrapper widget 在末尾追加。
  static const List<String> categories = [
    '家常',
    '川菜',
    '粤菜',
    '西式',
    '烘焙',
    '汤羹',
  ];

  /// 烹饪时间预设（分钟）。最后一个 120 在 UI 上展示为 "120+"，但点击仍写值 120。
  static const List<int> cookingMinutes = [15, 30, 45, 60, 90, 120];

  /// 食材单位预设。"自定义…" 由 unit_dropdown 在 sheet 末尾追加。
  static const List<String> units = [
    'g',
    'ml',
    'kg',
    '个',
    '把',
    '根',
    '颗',
    '片',
    '杯',
    '勺',
    '适量',
  ];
}
