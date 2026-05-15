import 'package:flutter/material.dart';
import '../../models/proposal.dart';
import '../../theme/app_theme.dart';

class ProvenanceBadge extends StatelessWidget {
  const ProvenanceBadge({super.key, required this.origin, required this.userEdited});
  final FieldOrigin origin;
  final bool userEdited;

  @override
  Widget build(BuildContext context) {
    final (color, tooltip) = switch ((origin, userEdited)) {
      (_, true) => (AppColors.fkWarn, '手改'),
      (FieldOrigin.ai, _) => (AppColors.primary, 'AI 推断'),
      (FieldOrigin.system, _) => (AppColors.outline, '系统'),
      (FieldOrigin.user, _) => (AppColors.fkWarn, '手填'),
    };
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
