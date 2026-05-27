import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';

/// 9 个食材分类的卡通线性 SVG icon。
///
/// SVG paths 直接移植自 FreshKeeper 设计稿 `ui.jsx::CatIcon` — 圆润手绘风、
/// 36×36 viewBox、strokeWidth 1.8、round cap & join。`color` 同时控制描边与
/// 装饰点 fill;调用方通过 `FkCategoryPalette.of(catId).ink` 拿配对色。
class CatIcon extends StatelessWidget {
  final String category;
  final double size;
  final Color color;
  final double strokeWidth;

  const CatIcon({
    super.key,
    required this.category,
    this.size = 28,
    this.color = AppColors.onSurface,
    this.strokeWidth = 1.8,
  });

  @override
  Widget build(BuildContext context) {
    final svg = _kCatSvg[category] ?? _kCatSvg['veg']!;
    final hex = _hex(color);
    final styled = svg
        .replaceAll('{stroke}', hex)
        .replaceAll('{fill}', hex)
        .replaceAll('{sw}', strokeWidth.toString());
    return SvgPicture.string(
      styled,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}

String _hex(Color c) {
  final r = (c.r * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

/// 9 个分类 SVG。`{stroke}` / `{fill}` / `{sw}` 占位符在渲染时被替换。
const Map<String, String> _kCatSvg = {
  'veg': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M18 7c-6 0-10 4-10 10 0 5 4 9 10 9s10-4 10-9C28 11 24 7 18 7z"/>
    <path d="M18 7c-2 4-2 8 0 13M18 26c2-4 4-7 8-9M18 26c-2-4-4-7-8-9M14 9c-1 3-1 6 1 8M22 9c1 3 1 6-1 8"/>
    <path d="M18 4c1 1 1 2 0 3M16 5c0 1 1 2 2 2s2-1 2-2"/>
  </g>
</svg>
''',
  'fruit': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M18 11c-5-2-10 1-10 7 0 5 4 10 10 10s10-5 10-10c0-6-5-9-10-7z"/>
    <path d="M18 11v-2"/>
    <path d="M18 9c1-3 4-4 6-3-1 3-3 5-6 4z"/>
    <circle cx="14.5" cy="17" r="0.8" fill="{fill}" stroke="none"/>
  </g>
</svg>
''',
  'meat': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M22 8c3 0 6 3 6 6 0 4-3 6-6 6-1 0-2 0-3-1l-4 4c-1 1-3 1-4 0s-1-3 0-4l4-4c-1-1-1-2-1-3 0-3 2-6 6-6 1 0 2 0 2 2z"/>
    <path d="M11 22l-3 3M9 23l3 3" stroke-width="1.6"/>
  </g>
</svg>
''',
  'sea': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M6 18c2-5 7-8 14-8 3 0 5 1 7 3-1 3-1 7 0 10-2 2-4 3-7 3-7 0-12-3-14-8z"/>
    <path d="M27 13l3-3v16l-3-3"/>
    <circle cx="24" cy="16" r="1" fill="{fill}" stroke="none"/>
    <path d="M9 16c3-1 7-1 10 2"/>
  </g>
</svg>
''',
  'dairy': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M11 10v18a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V10l-3-4h-8l-3 4z"/>
    <path d="M11 10h14"/>
    <path d="M15 18h6v6h-6z"/>
    <path d="M16 14h4"/>
  </g>
</svg>
''',
  'drink': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M10 11h16l-2 17a2 2 0 0 1-2 2H14a2 2 0 0 1-2-2l-2-17z"/>
    <path d="M10 14h16"/>
    <path d="M20 6l-2 8M20 6l3 1"/>
  </g>
</svg>
''',
  'sauce': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 14h12v14a2 2 0 0 1-2 2H14a2 2 0 0 1-2-2V14z"/>
    <path d="M11 14l1-4h12l1 4z"/>
    <circle cx="16" cy="19" r="0.8" fill="{fill}" stroke="none"/>
    <circle cx="20" cy="19" r="0.8" fill="{fill}" stroke="none"/>
    <circle cx="18" cy="22" r="0.8" fill="{fill}" stroke="none"/>
  </g>
</svg>
''',
  'grain': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M6 18h24c0 6-5 10-12 10S6 24 6 18z"/>
    <path d="M9 18c2-1 5-2 9-2s7 1 9 2"/>
    <path d="M14 11c-1 1-1 2 0 3M18 8c-1 1-1 2 0 3M22 11c-1 1-1 2 0 3" stroke-width="1.6"/>
  </g>
</svg>
''',
  'snack': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 36 36">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <circle cx="18" cy="18" r="11"/>
    <circle cx="14" cy="15" r="1.2" fill="{fill}" stroke="none"/>
    <circle cx="21" cy="13" r="1" fill="{fill}" stroke="none"/>
    <circle cx="22" cy="20" r="1.4" fill="{fill}" stroke="none"/>
    <circle cx="15" cy="22" r="1.1" fill="{fill}" stroke="none"/>
    <circle cx="19" cy="19" r="0.7" fill="{fill}" stroke="none"/>
  </g>
</svg>
''',
};

/// 已知食材分类 id 列表(便于测试与遍历)。
const List<String> kFkCategoryIds = [
  'veg', 'fruit', 'meat', 'sea', 'dairy', 'drink', 'sauce', 'grain', 'snack',
];
