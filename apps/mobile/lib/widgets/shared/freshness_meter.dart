import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';

class FreshnessMeter extends StatelessWidget {
  final double percent;
  final FreshnessState state;
  final bool showLabel;

  const FreshnessMeter({
    super.key,
    required this.percent,
    required this.state,
    this.showLabel = true,
  });

  Color get _barColor {
    switch (state) {
      case FreshnessState.fresh:
        return AppColors.primary;
      case FreshnessState.expiringSoon:
        return AppColors.secondary;
      case FreshnessState.urgent:
        return AppColors.error;
      case FreshnessState.expired:
        return AppColors.error;
    }
  }

  String get _label {
    switch (state) {
      case FreshnessState.fresh:
        return '新鲜度 ${(percent * 100).round()}%';
      case FreshnessState.expiringSoon:
      case FreshnessState.urgent:
        return '剩余 ${(percent * 100).round()}%';
      case FreshnessState.expired:
        return '新鲜度 0%';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: state == FreshnessState.expired ? 0.0 : percent.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(_barColor),
          ),
        ),
        if (showLabel) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '新鲜度指标',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: AppFontSize.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              Text(
                _label.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: AppFontSize.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                  color: _barColor,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

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
                  widthFactor: percent,
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
