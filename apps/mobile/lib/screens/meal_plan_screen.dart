import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/meal_plan_entry.dart';
import '../providers/meal_plan_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/meal_plan_day_label.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_empty_state.dart';
import '../widgets/shared/fk_top_bar.dart';
import '../widgets/shared/recipe_image.dart';

/// 每周膳食计划日历。
///
/// 渲染「今天起 7 天的滚动窗 ∪ 任何已有计划的日期」(并集,避免窗口外的计划被
/// 隐藏)。顶部缺料卡把未完成计划餐缺的食材一键加入购物清单。每条计划餐可标记
/// 完成 / 删除。「加入计划」入口在菜谱详情(后续接入)。
class MealPlanScreen extends ConsumerWidget {
  const MealPlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final byDay = ref.watch(mealPlanByDayProvider);
    final missing = ref.watch(mealPlanMissingIngredientsProvider);
    final today = MealPlanEntry.dateOnly(DateTime.now());

    // 7-day rolling window unioned with any day that already has entries, so a
    // meal planned in the past / further out is never silently hidden.
    final days =
        <DateTime>{
          for (var i = 0; i < 7; i++) today.add(Duration(days: i)),
          ...byDay.keys,
        }.toList()..sort();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            FkTopBar(
              title: '本周计划',
              subtitle: '排好这周吃什么 · 一键补缺料',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            if (missing.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                child: _MissingCard(
                  count: missing.length,
                  onTap: () => _addMissingToShopping(context, ref, missing),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            if (byDay.isEmpty)
              const FkEmptyState(
                icon: Icons.calendar_month_outlined,
                title: '还没有膳食计划',
                subtitle: '去菜谱页把想吃的加进某一天,这里就能看到一周安排',
              )
            else
              for (final day in days)
                _DaySection(
                  date: day,
                  today: today,
                  entries: byDay[day] ?? const [],
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _addMissingToShopping(
    BuildContext context,
    WidgetRef ref,
    List<String> names,
  ) async {
    var added = 0;
    try {
      for (final name in names) {
        if (await ref.read(shoppingProvider.notifier).addFromSuggestion(name)) {
          added++;
        }
      }
    } catch (_) {
      if (context.mounted) showAppSnackBar(context, '加入购物清单失败，请重试');
      return;
    }
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      added > 0 ? '已加入 $added 样食材到购物清单' : '缺的食材都已在购物清单中',
      backgroundColor: added > 0 ? AppColors.primary : AppColors.tertiary,
    );
  }
}

class _MissingCard extends StatelessWidget {
  const _MissingCard({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return FkCard(
      key: const ValueKey('mp-missing'),
      backgroundColor: AppColors.primarySoft,
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  Icons.add_shopping_cart_outlined,
                  size: 18,
                  color: AppColors.primaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '本周还缺 $count 样食材',
                  style: tt.labelLarge?.copyWith(
                    fontSize: AppFontSize.xs + 2,
                    color: AppColors.primaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '一键加入购物清单',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.primaryContainer.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: AppColors.primaryContainer,
          ),
        ],
      ),
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.date,
    required this.today,
    required this.entries,
  });

  final DateTime date;
  final DateTime today;
  final List<MealPlanEntry> entries;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
            child: Row(
              children: [
                Text(
                  mealPlanDayLabel(date, today),
                  style: tt.labelLarge?.copyWith(color: AppColors.onSurface),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${date.month}/${date.day}',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (entries.isEmpty)
            _EmptyDayCard()
          else
            FkCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < entries.length; i++)
                    _EntryRow(
                      entry: entries[i],
                      isLast: i == entries.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyDayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FkCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          const Icon(
            Icons.restaurant_outlined,
            size: 16,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '还没安排',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends ConsumerWidget {
  const _EntryRow({required this.entry, required this.isLast});

  final MealPlanEntry entry;
  final bool isLast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: AppColors.hair, width: 0.5)),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: SizedBox(
              width: 44,
              height: 44,
              child: RecipeImage(
                imageSource: entry.recipeImageUrl,
                fit: BoxFit.cover,
                fallback: Container(
                  color: AppColors.primarySoft,
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.restaurant_menu,
                    size: 22,
                    color: AppColors.primaryContainer,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.recipeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelLarge?.copyWith(
                    color: entry.done
                        ? AppColors.onSurfaceVariant
                        : AppColors.onSurface,
                    decoration: entry.done ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.servings} 份',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: ValueKey('mp-done-${entry.id}'),
            visualDensity: VisualDensity.compact,
            tooltip: entry.done ? '标记未做' : '标记已做',
            icon: Icon(
              entry.done
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 22,
              color: entry.done ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
            onPressed: () =>
                ref.read(mealPlanProvider.notifier).setDone(entry.id, !entry.done),
          ),
          IconButton(
            key: ValueKey('mp-del-${entry.id}'),
            visualDensity: VisualDensity.compact,
            tooltip: '删除',
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
            onPressed: () =>
                ref.read(mealPlanProvider.notifier).remove(entry.id),
          ),
        ],
      ),
    );
  }
}

