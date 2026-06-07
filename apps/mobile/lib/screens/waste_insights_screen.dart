import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/food_log_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_empty_state.dart';
import '../widgets/shared/fk_top_bar.dart';

/// 减废成效统计屏:用掉/浪费/抢救临期 + 用掉率 + 最常浪费分类,可切时间窗
/// (本月 / 近 30 天 / 近 90 天)。
///
/// 数据来自 [foodLogWindowStatsProvider] / [foodLogWastedByCategoryForWindowProvider]
/// (随 [wasteStatsWindowProvider] 变)——做菜扣减自动记消耗,手动删除时选
/// 「吃完/扔了」记真值。
class WasteInsightsScreen extends ConsumerWidget {
  const WasteInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(wasteStatsWindowProvider);
    final stats = ref.watch(foodLogWindowStatsProvider);
    final byCategory = ref.watch(foodLogWastedByCategoryForWindowProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => ref.read(foodLogProvider.notifier).reload(),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 40),
            children: [
              FkTopBar(
                title: '减废成效',
                subtitle: '${window.label}用掉与浪费 · 越用越省',
                onBack: () => Navigator.of(context).maybePop(),
              ),
              _WindowSelector(
                selected: window,
                onSelect: (w) =>
                    ref.read(wasteStatsWindowProvider.notifier).state = w,
              ),
              if (stats.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: FkEmptyState(
                    icon: Icons.eco_outlined,
                    title: '${window.label}还没有减废记录',
                    subtitle: '做菜用掉、或清理食材时选「吃完 / 扔了」,这里就会统计你的成效',
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: _HeadlineCard(stats: stats, windowLabel: window.label),
                ),
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          label: '用掉',
                          value: stats.consumed,
                          tint: AppColors.primary,
                          soft: AppColors.primarySoft,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _MetricTile(
                          label: '浪费',
                          value: stats.wasted,
                          tint: AppColors.fkDanger,
                          soft: AppColors.tertiaryContainer,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _MetricTile(
                          label: '抢救临期',
                          value: stats.rescued,
                          tint: AppColors.fkWarn,
                          soft: AppColors.fkWarnSoft,
                        ),
                      ),
                    ],
                  ),
                ),
                if (byCategory.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xl),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Text(
                      '最常浪费',
                      style: TextStyle(
                        fontSize: AppFontSize.md,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final c in byCategory)
                    _CategoryRow(category: c.category, count: c.count),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 时间窗切换:本月 / 近 30 天 / 近 90 天(90 天对齐内存窗 [foodLogRecentWindow])。
/// 始终显示,即便当前窗为空也能切到有数据的窗。
class _WindowSelector extends StatelessWidget {
  const _WindowSelector({required this.selected, required this.onSelect});

  final WasteStatsWindow selected;
  final ValueChanged<WasteStatsWindow> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.xs,
        AppSpacing.xl,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (final w in WasteStatsWindow.values) ...[
            _WindowChip(
              label: w.label,
              active: w == selected,
              onTap: () => onSelect(w),
            ),
            if (w != WasteStatsWindow.values.last)
              const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// 顶部「用掉率」大数字卡:用掉占比越高越省。
class _HeadlineCard extends StatelessWidget {
  const _HeadlineCard({required this.stats, required this.windowLabel});

  final FoodLogStats stats;
  final String windowLabel;

  @override
  Widget build(BuildContext context) {
    final usedPct = stats.total == 0
        ? 0
        : (stats.consumed / stats.total * 100).round();
    return FkCard(
      backgroundColor: AppColors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$windowLabel用掉率',
            style: const TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$usedPct%',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$windowLabel共处理 ${stats.total} 样食材',
            style: const TextStyle(
              fontSize: AppFontSize.sm,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.tint,
    required this.soft,
  });

  final String label;
  final int value;
  final Color tint;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text(
            '$value',
            style: TextStyle(
              fontSize: AppFontSize.xl,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppFontSize.xs,
              fontWeight: FontWeight.w600,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.category, required this.count});

  final String category;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: 6,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              category,
              style: const TextStyle(
                fontSize: AppFontSize.md,
                color: AppColors.onSurface,
              ),
            ),
          ),
          Text(
            '$count 样',
            style: const TextStyle(
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w600,
              color: AppColors.fkDanger,
            ),
          ),
        ],
      ),
    );
  }
}
