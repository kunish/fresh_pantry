import 'package:flutter/material.dart';

/// 虚线圆角描边。
///
/// Flutter 原生 `Border` 不支持 dashed,这里用 `CustomPaint` 还原设计稿
/// (`screens-3.jsx`)里的虚线框:菜谱「缺少」食材的勾选圈与标签、购物清单
/// 「清空已完成」按钮。半径取 [AppRadius.pill] 时会渲染成胶囊/圆形。
class FkDashedBorder extends StatelessWidget {
  final Widget child;
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;

  /// 可选填充色(画在虚线下方),用于「缺少」白底圈等场景。
  final Color? fillColor;

  const FkDashedBorder({
    super.key,
    required this.child,
    required this.color,
    this.strokeWidth = 1,
    this.radius = 12,
    this.dashLength = 4,
    this.gapLength = 3,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: color,
        strokeWidth: strokeWidth,
        radius: radius,
        dashLength: dashLength,
        gapLength: gapLength,
        fillColor: fillColor,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double radius;
  final double dashLength;
  final double gapLength;
  final Color? fillColor;

  _DashedRRectPainter({
    required this.color,
    required this.strokeWidth,
    required this.radius,
    required this.dashLength,
    required this.gapLength,
    required this.fillColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final r = (radius - inset).clamp(0.0, rect.shortestSide / 2);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(r));

    if (fillColor != null) {
      canvas.drawRRect(rrect, Paint()..color = fillColor!);
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final path = Path()..addRRect(rrect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = distance + dashLength;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0.0, metric.length)),
          paint,
        );
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRectPainter o) =>
      o.color != color ||
      o.strokeWidth != strokeWidth ||
      o.radius != radius ||
      o.dashLength != dashLength ||
      o.gapLength != gapLength ||
      o.fillColor != fillColor;
}
