import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/food_log_provider.dart';
import '../../screens/waste_insights_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/page_transitions.dart';
import '../../utils/safe_push.dart';
import '../shared/fk_card.dart';

/// Dashboard 入口卡:本月减废成效(用掉/浪费)。
///
/// 只在**有数据时**显示——空态不占首页(发现性靠 Settings 入口),一旦有记录就以
/// 正向「成效」面呈现,点进统计屏看用掉率/抢救临期/分类浪费。
class WasteInsightsCard extends ConsumerWidget {
  const WasteInsightsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(foodLogMonthStatsProvider);
    if (stats.isEmpty) return const SizedBox.shrink();

    final subtitle = stats.wasted == 0
        ? '本月用掉 ${stats.consumed} 样 · 零浪费 👏'
        : '本月用掉 ${stats.consumed} · 浪费 ${stats.wasted}';

    return FkCard(
      key: const ValueKey('dash-waste-insights'),
      onTap: () => pushRouteOnce(
        context,
        fkRoute<void>(builder: (_) => const WasteInsightsScreen()),
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
              Icons.eco_outlined,
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
                  '减废成效',
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
          if (stats.rescued > 0) ...[
            _RescuedBadge(count: stats.rescued),
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

class _RescuedBadge extends StatelessWidget {
  const _RescuedBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.fkWarnSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        '抢救 $count',
        style: const TextStyle(
          fontSize: AppFontSize.xs,
          fontWeight: FontWeight.w600,
          color: AppColors.onSecondaryContainer,
        ),
      ),
    );
  }
}
