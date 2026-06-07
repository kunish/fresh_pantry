import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_log_entry.dart';
import '../theme/app_theme.dart';

/// 删除食材时的「轻量追问」:这样东西是吃完/用掉了,还是没吃完扔了?
///
/// 返回用户选择的 [FoodLogOutcome];取消或点击空白返回 null(此时调用方应放弃删除)。
/// 这是减废成效统计的真值入口——做菜扣减自动算消耗,手动删除靠这里区分。
Future<FoodLogOutcome?> showFoodDepartureOutcomeSheet(
  BuildContext context, {
  String? itemName,
  int count = 1,
}) {
  final title = itemName != null ? '「$itemName」要移除' : '移除 $count 样食材';
  return showModalBottomSheet<FoodLogOutcome>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '它怎么了?用于统计你的减废成效',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.sm,
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _OutcomeTile(
              key: const ValueKey('departure-consumed'),
              icon: Icons.check_circle_outline_rounded,
              label: '吃完 / 用掉了',
              tint: AppColors.primary,
              tintSoft: AppColors.primarySoft,
              onTap: () => Navigator.pop(ctx, FoodLogOutcome.consumed),
            ),
            const SizedBox(height: AppSpacing.sm),
            _OutcomeTile(
              key: const ValueKey('departure-wasted'),
              icon: Icons.delete_sweep_outlined,
              label: '没吃完,扔了',
              tint: AppColors.error,
              tintSoft: AppColors.fkWarnSoft,
              onTap: () => Navigator.pop(ctx, FoodLogOutcome.wasted),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              key: const ValueKey('departure-cancel'),
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                '取消',
                style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _OutcomeTile extends StatelessWidget {
  const _OutcomeTile({
    super.key,
    required this.icon,
    required this.label,
    required this.tint,
    required this.tintSoft,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final Color tintSoft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: tintSoft,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Icon(icon, color: tint, size: 24),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.md,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
