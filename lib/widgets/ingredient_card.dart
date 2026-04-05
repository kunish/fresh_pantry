import 'package:flutter/material.dart';
import '../models/ingredient.dart';
import '../theme/app_theme.dart';
import 'freshness_meter.dart';

class IngredientCard extends StatelessWidget {
  final Ingredient ingredient;

  const IngredientCard({super.key, required this.ingredient});

  Color get _badgeBg {
    switch (ingredient.state) {
      case FreshnessState.fresh:
        return AppColors.primaryContainer;
      case FreshnessState.expiringSoon:
        return AppColors.secondaryContainer;
      case FreshnessState.expired:
        return AppColors.errorContainer;
    }
  }

  Color get _badgeText {
    switch (ingredient.state) {
      case FreshnessState.fresh:
        return AppColors.onPrimaryContainer;
      case FreshnessState.expiringSoon:
        return AppColors.onSecondaryContainer;
      case FreshnessState.expired:
        return AppColors.onErrorContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpired = ingredient.state == FreshnessState.expired;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 80,
                  height: 80,
                  child: Opacity(
                    opacity: isExpired ? 0.6 : 1.0,
                    child: ColorFiltered(
                      colorFilter: isExpired
                          ? const ColorFilter.mode(Colors.grey, BlendMode.saturation)
                          : const ColorFilter.mode(Colors.transparent, BlendMode.dst),
                      child: Image.network(
                        ingredient.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: AppColors.surfaceContainerLow,
                          child: const Icon(Icons.restaurant, color: AppColors.outline),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
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
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface.withValues(alpha: isExpired ? 0.6 : 1.0),
                            ),
                          ),
                        ),
                        Icon(Icons.more_vert, color: AppColors.outline, size: 20),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${ingredient.quantity} \u2022 ${ingredient.unit}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant.withValues(alpha: isExpired ? 0.6 : 1.0),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (ingredient.expiryLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _badgeBg,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          ingredient.expiryLabel!.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: _badgeText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FreshnessMeter(
            percent: ingredient.freshnessPercent,
            state: ingredient.state,
          ),
        ],
      ),
    );
  }
}
