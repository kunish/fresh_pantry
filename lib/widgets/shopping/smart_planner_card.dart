import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class SmartPlannerCard extends StatelessWidget {
  final String title;
  final VoidCallback? onViewRecipe;

  const SmartPlannerCard({
    super.key,
    required this.title,
    this.onViewRecipe,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '智能规划',
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.xs,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                  color: AppColors.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                title,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: AppFontSize.xl,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onPrimaryContainer,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                button: onViewRecipe != null,
                label: '查看食谱',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onViewRecipe,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '查看食谱',
                          style: GoogleFonts.manrope(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            fontSize: AppFontSize.md,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(
                          Icons.arrow_forward,
                          color: AppColors.primary,
                          size: 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            right: -8,
            bottom: -8,
            child: Icon(
              Icons.restaurant,
              size: 120,
              color: AppColors.onPrimaryContainer.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}
