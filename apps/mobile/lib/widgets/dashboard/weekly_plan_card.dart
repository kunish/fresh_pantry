import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/meal_plan_provider.dart';
import '../../screens/meal_plan_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/page_transitions.dart';
import '../../utils/safe_push.dart';
import '../shared/fk_card.dart';

/// Dashboard 入口卡:把「本周膳食计划」提到首页(此前只在 Settings 可达)。
///
/// 始终可见——膳食计划是核心功能,空态也展示「去规划」邀请以保证可发现性
/// (竞品普遍把膳食计划放在显眼处)。卡片本身只负责导航;缺料的「一键加购」由
/// 膳食计划屏内的缺料卡完成,这里仅用 badge 提示,避免出现第二个加购入口。
class WeeklyPlanCard extends ConsumerWidget {
  const WeeklyPlanCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(mealPlanWeekSummaryProvider);
    final hasPlan = summary.upcoming > 0;

    final subtitle = !hasPlan
        ? '还没安排 — 点这里规划这周吃什么'
        : summary.today > 0
        ? '本周已排 ${summary.upcoming} 顿 · 今天 ${summary.today} 顿'
        : '本周已排 ${summary.upcoming} 顿';

    return FkCard(
      key: const ValueKey('dash-weekly-plan'),
      onTap: () => pushRouteOnce(
        context,
        fkRoute<void>(builder: (_) => const MealPlanScreen()),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: const Icon(
              Icons.calendar_month_outlined,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '本周计划',
                  style: TextStyle(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppFontSize.sm,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (summary.missing > 0) ...[
            _MissingBadge(count: summary.missing),
            const SizedBox(width: AppSpacing.sm),
          ],
          const Icon(
            Icons.chevron_right,
            color: AppColors.onSurfaceVariant,
            size: 22,
          ),
        ],
      ),
    );
  }
}

class _MissingBadge extends StatelessWidget {
  const _MissingBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.fkWarnSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        '还缺 $count 样',
        style: const TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          color: AppColors.onSecondaryContainer,
        ),
      ),
    );
  }
}
