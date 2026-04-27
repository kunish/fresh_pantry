import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/recipe.dart';
import '../theme/app_theme.dart';
import 'shared/recipe_image.dart';

class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final int? matchedCount;
  final String? subtitle;
  final String? ingredientLabel;
  final Widget? trailing;
  final VoidCallback? onTap;

  const RecipeCard({
    super.key,
    required this.recipe,
    this.matchedCount,
    this.subtitle,
    this.ingredientLabel,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ingredientText =
        ingredientLabel ??
        '${matchedCount ?? 0}/${recipe.ingredients.length} 已备';

    return Semantics(
      button: onTap != null,
      label: recipe.name,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            children: [
              // Thumbnail
              ClipRRect(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                child: RecipeImage(
                  imageSource: recipe.imageUrl,
                  width: 96,
                  height: 96,
                  fit: BoxFit.cover,
                  fallback: Container(
                    width: 96,
                    height: 96,
                    color: AppColors.surfaceContainerLow,
                    child: const Icon(
                      Icons.restaurant,
                      color: AppColors.outline,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Info
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipe.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle ?? recipe.description,
                        style: GoogleFonts.manrope(
                          fontSize: 12,
                          color: AppColors.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _buildMetadataItem(
                            Icons.timer_outlined,
                            '${recipe.cookingMinutes}分钟',
                          ),
                          _buildMetadataItem(
                            Icons.local_fire_department_outlined,
                            recipe.difficultyLabel,
                            iconColor: AppColors.secondary,
                          ),
                          _buildMetadataItem(
                            Icons.checklist,
                            ingredientText,
                            iconColor: AppColors.primary,
                            textColor: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              trailing ??
                  const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.chevron_right,
                      color: AppColors.outline,
                      size: 20,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataItem(
    IconData icon,
    String label, {
    Color? iconColor,
    Color? textColor,
    FontWeight fontWeight = FontWeight.w400,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor ?? AppColors.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 11,
            fontWeight: fontWeight,
            color: textColor ?? AppColors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
