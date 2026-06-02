import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';

class GradientFreshnessMeter extends StatelessWidget {
  final double percent;

  const GradientFreshnessMeter({super.key, required this.percent});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '最佳新鲜',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
            Text(
              '即将到期',
              style: TextStyle(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: AppColors.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: percent.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.tertiaryFixedDim,
                          AppColors.secondaryContainer,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
