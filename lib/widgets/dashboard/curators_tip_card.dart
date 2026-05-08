import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class CuratorsTipCard extends StatelessWidget {
  final String tip;
  final String bottomLabel;

  const CuratorsTipCard({
    super.key,
    required this.tip,
    this.bottomLabel = '食谱推荐已就绪',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '管家小贴士',
            style: GoogleFonts.plusJakartaSans(
              fontSize: AppFontSize.xl,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '"$tip"',
            style: GoogleFonts.manrope(
              color: AppColors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            bottomLabel.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: AppFontSize.xs,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
