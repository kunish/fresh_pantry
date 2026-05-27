import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class StatCard extends StatelessWidget {
  final String value;
  final String label;
  final bool isWarning;
  final VoidCallback? onTap;
  final String? semanticLabel;

  const StatCard({
    super.key,
    required this.value,
    required this.label,
    this.isWarning = false,
    this.onTap,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
        boxShadow: [
          BoxShadow(
            color: AppColors.onSurface.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: AppFontSize.xxxl,
              fontWeight: FontWeight.w700,
              color: isWarning ? AppColors.secondary : AppColors.primary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.manrope(
              fontSize: AppFontSize.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Semantics(
      button: true,
      label: semanticLabel ?? '$value $label',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      ),
    );
  }
}
