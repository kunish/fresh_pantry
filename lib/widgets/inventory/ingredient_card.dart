import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';
import '../../utils/storage_labels.dart';
import '../shared/category_icon.dart';
import '../shared/freshness_meter.dart';

({Color bg, Color text}) freshnessBadgeColors(FreshnessState state) {
  switch (state) {
    case FreshnessState.fresh:
      return (bg: AppColors.primaryFixed, text: AppColors.primary);
    case FreshnessState.expiringSoon:
      return (
        bg: AppColors.secondaryContainer,
        text: AppColors.onSecondaryContainer,
      );
    case FreshnessState.expired:
      return (bg: AppColors.errorContainer, text: AppColors.onErrorContainer);
  }
}

class IngredientCard extends StatelessWidget {
  final Ingredient ingredient;
  final VoidCallback? onBuyAgain;
  final VoidCallback? onTap;

  const IngredientCard({
    super.key,
    required this.ingredient,
    this.onBuyAgain,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isExpired = ingredient.state == FreshnessState.expired;
    final badgeColors = freshnessBadgeColors(ingredient.state);

    final cardContent = Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(
                opacity: isExpired ? 0.6 : 1.0,
                child: CategoryIconAvatar(
                  category: ingredient.category,
                  size: 80,
                  iconSize: 34,
                  muted: isExpired,
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            ingredient.name,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(
                              fontSize: AppFontSize.lg,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface.withValues(
                                alpha: isExpired ? 0.6 : 1.0,
                              ),
                            ),
                          ),
                        ),
                        if (onTap != null)
                          Icon(
                            Icons.chevron_right,
                            color: AppColors.outline,
                            size: 20,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${ingredient.quantity} \u2022 ${ingredient.unit}',
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        color: AppColors.onSurfaceVariant.withValues(
                          alpha: isExpired ? 0.6 : 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        if (ingredient.expiryLabel != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            decoration: BoxDecoration(
                              color: badgeColors.bg,
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: Text(
                              ingredient.expiryLabel!.toUpperCase(),
                              style: TextStyle(
                                fontSize: AppFontSize.xs,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: badgeColors.text,
                              ),
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            borderRadius: BorderRadius.all(
                              Radius.circular(AppRadius.pill),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                storageIconFor(ingredient.storage),
                                size: 12,
                                color: AppColors.onSurfaceVariant,
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Text(
                                storageLabelFor(ingredient.storage),
                                style: const TextStyle(
                                  fontSize: AppFontSize.xs,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FreshnessMeter(
            percent: ingredient.freshnessPercent,
            state: ingredient.state,
          ),
          if (onBuyAgain != null &&
              ingredient.state != FreshnessState.fresh) ...[
            const SizedBox(height: AppSpacing.md),
            GestureDetector(
              onTap: onBuyAgain,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                decoration: const BoxDecoration(
                  color: AppColors.secondaryContainer,
                  borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.replay,
                      size: 16,
                      color: AppColors.onSecondaryContainer,
                    ),
                    SizedBox(width: AppSpacing.sm),
                    Text(
                      '再买一次',
                      style: TextStyle(
                        fontSize: AppFontSize.sm,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSecondaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: cardContent,
      );
    }
    return cardContent;
  }
}
