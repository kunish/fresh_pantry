import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../theme/app_theme.dart';

/// 5 个冰箱存储区(冷藏 / 冷冻 / 门架 / 保鲜盒 / 常温)的卡通线性 SVG icon。
///
/// SVG paths 移植自 FreshKeeper 设计稿 `ui.jsx::ZoneIcon` — 24×24 viewBox、
/// strokeWidth 1.7、round cap & join。
class ZoneIcon extends StatelessWidget {
  final String zone;
  final double size;
  final Color color;
  final double strokeWidth;

  const ZoneIcon({
    super.key,
    required this.zone,
    this.size = 16,
    this.color = AppColors.outline,
    this.strokeWidth = 1.7,
  });

  @override
  Widget build(BuildContext context) {
    final svg = _kZoneSvg[zone] ?? _kZoneSvg['fridge']!;
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

const Map<String, String> _kZoneSvg = {
  'fridge': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M6 3h12a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/>
    <path d="M4 11h16M8 7v1M8 14v2"/>
  </g>
</svg>
''',
  'freezer': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M12 4v16M5 8l14 8M5 16l14-8"/>
    <path d="M12 4l-2 2M12 4l2 2M12 20l-2-2M12 20l2-2"/>
  </g>
</svg>
''',
  'door': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M6 3h12v18H6zM6 3l-2 2v14l2 2"/>
    <circle cx="14" cy="12" r="0.8" fill="{fill}" stroke="none"/>
  </g>
</svg>
''',
  'box': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M4 7l8-3 8 3v10l-8 3-8-3V7z"/>
    <path d="M4 7l8 3 8-3M12 10v10"/>
  </g>
</svg>
''',
  'pantry': '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">
  <g fill="none" stroke="{stroke}" stroke-width="{sw}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M4 6h16v12H4z"/>
    <path d="M4 12h16M9 6v12M15 6v12"/>
  </g>
</svg>
''',
};

const List<String> kFkZoneIds = ['fridge', 'freezer', 'door', 'box', 'pantry'];

const Map<String, String> kFkZoneNames = {
  'fridge': '冷藏区',
  'freezer': '冷冻区',
  'door': '门架',
  'box': '保鲜盒',
  'pantry': '常温',
};
