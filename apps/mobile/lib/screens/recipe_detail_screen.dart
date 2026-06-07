import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/food_knowledge.dart';
import '../models/meal_plan_entry.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../providers/deduction_review_provider.dart';
import '../providers/favorite_recipes_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/meal_plan_provider.dart';
import '../providers/recipe_provider.dart';
import '../providers/shopping_provider.dart';
import '../services/deduction_proposal_factory.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../utils/meal_plan_day_label.dart';
import '../utils/page_transitions.dart';
import '../utils/quantity_text.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_dashed_border.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/recipe_cover_fallback.dart';
import '../widgets/shared/recipe_image.dart';
import 'deduction_review_screen.dart';
import 'meal_plan_screen.dart';

/// 设计稿 `screens-3.jsx::RecipeDetailScreen`。
///
/// 视觉栈:大 hero 图(260px)+ 浮 back/收藏 → 标题 + 时间/难度 + 标签 →
/// 食材清单(缺少项 dangerSoft 高亮 + dashed border)→ 一键加购缺少 CTA →
/// 步骤卡(圆形 step number + 可点完成切换)→ 底部 "开始烹饪" primary CTA。
class RecipeDetailScreen extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isCustomRecipe;

  /// 该菜谱是否从"用临期"入口进入 — 控制标题下方是否展示临期 pill。
  final bool useExpiring;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    this.isCustomRecipe = false,
    this.useExpiring = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  final Set<int> _completedSteps = <int>{};
  bool _addingToCart = false;

  /// 备料倍数:1× 即食谱原始用量,缩放只作用于展示与加购,不改存储。
  double _scaleFactor = 1.0;

  @override
  void didUpdateWidget(covariant RecipeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recipe.id != widget.recipe.id ||
        !listEquals(oldWidget.recipe.steps, widget.recipe.steps)) {
      _completedSteps.clear();
      _scaleFactor = 1.0;
    }
  }

  void _toggleStep(int index) {
    setState(() {
      if (_completedSteps.contains(index)) {
        _completedSteps.remove(index);
      } else {
        _completedSteps.add(index);
      }
    });
  }

  Future<void> _addMissingToCart(List<RecipeIngredient> missing) async {
    if (_addingToCart) return;
    setState(() => _addingToCart = true);
    var addedCount = 0;
    try {
      for (final ing in missing) {
        final added = await ref
            .read(shoppingProvider.notifier)
            .add(
              ShoppingItem(
                id: '${ShoppingItem.newId()}_${ing.name}',
                name: ing.name,
                detail: ing.amount,
                category: FoodKnowledge.categoryFor(ing.name),
              ),
            );
        if (added) addedCount++;
      }
    } on Object {
      if (mounted) showAppSnackBar(context, '加入购物清单失败，请重试');
      return;
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      addedCount == 0 ? '缺失食材已在购物清单中' : '已将 $addedCount 个食材加入购物清单',
      backgroundColor: addedCount == 0 ? AppColors.tertiary : AppColors.primary,
    );
  }

  void _startCooking() {
    final message = widget.recipe.steps.isEmpty ? '暂无烹饪步骤' : '已开始烹饪，点击步骤可标记完成';
    showAppSnackBar(context, message);
  }

  /// 弹出未来 7 天选择器,把本菜谱加入选中那天的膳食计划。
  Future<void> _addToPlan() async {
    final today = MealPlanEntry.dateOnly(DateTime.now());
    final chosen = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _PlanDayPickerSheet(today: today),
    );
    if (chosen == null || !mounted) return;
    try {
      await ref
          .read(mealPlanProvider.notifier)
          .addEntry(date: chosen, recipe: widget.recipe);
    } catch (_) {
      if (mounted) showAppSnackBar(context, '加入计划失败，请重试');
      return;
    }
    if (!mounted) return;
    showAppSnackBar(
      context,
      '已加入「${mealPlanDayLabel(chosen, today)}」的计划',
      backgroundColor: AppColors.primary,
      actionLabel: '查看',
      onAction: () => Navigator.of(
        context,
      ).push(fkRoute<void>(builder: (_) => const MealPlanScreen())),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(inventoryProvider.select(inventoryNamesSignature));
    final inventoryNames = inventoryNameSet(ref.read(inventoryProvider));
    final matched = matchedIngredientCountForNames(
      inventoryNames,
      widget.recipe,
    );
    final missing = missingRecipeIngredientsForNames(
      inventoryNames,
      widget.recipe,
    );

    final stepProgress = widget.recipe.steps.isEmpty
        ? 0.0
        : _completedSteps.length / widget.recipe.steps.length;

    final isFavorite = ref.watch(isRecipeFavoriteProvider(widget.recipe.id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _HeroSection(
            recipe: widget.recipe,
            isFavorite: isFavorite,
            isCustom: widget.isCustomRecipe,
            onBack: () => Navigator.of(context).maybePop(),
            onAddToPlan: _addToPlan,
            onToggleFavorite: () => ref
                .read(favoriteRecipesProvider.notifier)
                .toggle(widget.recipe.id),
            onEdit: widget.onEdit,
            onDelete: widget.onDelete,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              18,
              AppSpacing.xl,
              18,
              AppSpacing.huge,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.recipe.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.xxl,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DefaultTextStyle.merge(
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    color: AppColors.onSurfaceVariant,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        size: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text('${widget.recipe.cookingMinutes} 分钟'),
                      const SizedBox(width: 14),
                      const Icon(
                        Icons.local_fire_department_outlined,
                        size: 13,
                        color: AppColors.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(widget.recipe.difficultyLabel),
                    ],
                  ),
                ),
                if (widget.recipe.description.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    widget.recipe.description,
                    style: GoogleFonts.manrope(
                      fontSize: AppFontSize.md,
                      height: 1.6,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (widget.recipe.tags.isNotEmpty || widget.useExpiring) ...[
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final tag in widget.recipe.tags)
                        FkPill(
                          label: tag,
                          backgroundColor: AppColors.primarySoft,
                          foregroundColor: AppColors.primaryContainer,
                        ),
                      if (widget.useExpiring)
                        const FkPill(
                          label: '使用临期食材',
                          leading: Icon(Icons.local_fire_department_rounded),
                          backgroundColor: AppColors.fkWarnSoft,
                          foregroundColor: AppColors.fkWarnInk,
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                _IngredientsSection(
                  recipe: widget.recipe,
                  inventoryNames: inventoryNames,
                  matched: matched,
                  missingCount: missing.length,
                  scaleFactor: _scaleFactor,
                  onScaleChanged: (f) => setState(() => _scaleFactor = f),
                ),
                if (missing.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _AddMissingCta(
                    count: missing.length,
                    loading: _addingToCart,
                    onTap: () => _addMissingToCart(
                      missing.map((i) => i.scaledBy(_scaleFactor)).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
                _StepsSection(
                  steps: widget.recipe.steps,
                  completed: _completedSteps,
                  progress: stepProgress,
                  onToggleStep: _toggleStep,
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  key: const Key('recipe_cooked_action'),
                  icon: const Icon(Icons.restaurant),
                  label: const Text('我做了'),
                  onPressed: () async {
                    final inv = ref.read(inventoryProvider);
                    final proposals = DeductionProposalFactory.forRecipe(
                      widget.recipe,
                      inv,
                    );
                    ref.read(deductionReviewProvider.notifier).seed(proposals);
                    await Navigator.of(context).push(
                      fkRoute<void>(
                        builder: (_) => const DeductionReviewScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                _StartCookingButton(onTap: _startCooking),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  final Recipe recipe;
  final bool isFavorite;
  final bool isCustom;
  final VoidCallback onBack;
  final VoidCallback onAddToPlan;
  final VoidCallback onToggleFavorite;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _HeroSection({
    required this.recipe,
    required this.isFavorite,
    required this.isCustom,
    required this.onBack,
    required this.onAddToPlan,
    required this.onToggleFavorite,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final heroHeight = (screenHeight * 0.32).clamp(200.0, 260.0);
    return SizedBox(
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'recipe-image-${recipe.id}',
            child: RecipeImage(
              imageSource: recipe.imageUrl,
              fit: BoxFit.cover,
              semanticLabel: recipe.name,
              fallback: RecipeCoverFallback(
                category: recipe.category,
                iconSize: 64,
              ),
            ),
          ),
          // Top scrim so floating chrome stays readable on dark covers
          IgnorePointer(
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: MediaQuery.of(context).padding.top + 64,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, AppSpacing.sm, 18, 0),
              child: Row(
                children: [
                  FkIconButton(
                    onTap: onBack,
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  if (isCustom && onEdit != null) ...[
                    Tooltip(
                      message: '编辑食谱',
                      child: FkIconButton(
                        onTap: onEdit!,
                        child: const Icon(Icons.edit_outlined, size: 18),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  if (isCustom && onDelete != null) ...[
                    Tooltip(
                      message: '删除食谱',
                      child: FkIconButton(
                        onTap: onDelete!,
                        foregroundColor: AppColors.fkDanger,
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Tooltip(
                    message: '加入膳食计划',
                    child: FkIconButton(
                      key: const Key('recipe_add_to_plan_action'),
                      onTap: onAddToPlan,
                      child: const Icon(
                        Icons.calendar_month_outlined,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  FkIconButton(
                    onTap: onToggleFavorite,
                    foregroundColor: isFavorite
                        ? AppColors.fkDanger
                        : AppColors.onSurface,
                    child: Icon(
                      isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_outline_rounded,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 备料倍数预设:覆盖最常见的半倍/原始/双倍/三倍场景。
const List<double> _scalePresets = [0.5, 1.0, 2.0, 3.0];

String _scaleLabel(double factor) =>
    factor == 0.5 ? '½×' : '${formatQuantity(factor)}×';

class _IngredientsSection extends StatelessWidget {
  final Recipe recipe;
  final Set<String> inventoryNames;
  final int matched;
  final int missingCount;
  final double scaleFactor;
  final ValueChanged<double> onScaleChanged;

  const _IngredientsSection({
    required this.recipe,
    required this.inventoryNames,
    required this.matched,
    required this.missingCount,
    required this.scaleFactor,
    required this.onScaleChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Only offer portion scaling when at least one ingredient carries a numeric
    // magnitude — otherwise the control would be a dead no-op.
    final canScale = recipe.ingredients.any((i) => i.isScalable);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '食材清单',
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const Spacer(),
            Text(
              '已有 $matched/${recipe.ingredients.length}',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.sm,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        if (canScale) ...[
          const SizedBox(height: 10),
          _ScaleSelector(selected: scaleFactor, onSelect: onScaleChanged),
        ],
        const SizedBox(height: 10),
        FkCard(
          padding: EdgeInsets.zero,
          child: ListView.builder(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recipe.ingredients.length,
            itemBuilder: (context, index) {
              final ingredient = recipe.ingredients[index];
              return _IngredientRow(
                index: index,
                ingredient: ingredient.scaledBy(scaleFactor),
                isAvailable: recipeIngredientMatchesInventory(
                  ingredient,
                  inventoryNames,
                ),
                isLast: index == recipe.ingredients.length - 1,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 备料倍数分段控件,视觉沿用 waste_insights 的 chip 行(`_WindowChip`)。
class _ScaleSelector extends StatelessWidget {
  const _ScaleSelector({required this.selected, required this.onSelect});

  final double selected;
  final ValueChanged<double> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '备料倍数',
      child: Row(
        children: [
          const Icon(
            Icons.straighten_rounded,
            size: 15,
            color: AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          for (final f in _scalePresets) ...[
            _ScaleChip(
              label: _scaleLabel(f),
              active: f == selected,
              onTap: () => onSelect(f),
            ),
            if (f != _scalePresets.last) const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _ScaleChip extends StatelessWidget {
  const _ScaleChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppFontSize.sm,
            fontWeight: FontWeight.w700,
            color: active ? Colors.white : AppColors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _IngredientRow extends StatelessWidget {
  final int index;
  final RecipeIngredient ingredient;
  final bool isAvailable;
  final bool isLast;

  const _IngredientRow({
    required this.index,
    required this.ingredient,
    required this.isAvailable,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('ingredient_$index'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isAvailable ? Colors.transparent : AppColors.fkDangerSoft,
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.hair, width: 0.5),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _StatusMark(isAvailable: isAvailable),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ingredient.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.md,
                    fontWeight: FontWeight.w600,
                    color: isAvailable
                        ? AppColors.onSurface
                        : AppColors.fkDanger,
                  ),
                ),
                if (ingredient.amount.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    ingredient.amount,
                    style: GoogleFonts.manrope(
                      fontSize: AppFontSize.xs,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          isAvailable
              ? FkPill(
                  label: '已有',
                  sm: true,
                  backgroundColor: AppColors.primarySoft,
                  foregroundColor: AppColors.primaryContainer,
                )
              : FkDashedBorder(
                  radius: AppRadius.pill,
                  color: AppColors.fkDanger,
                  fillColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Text(
                      '缺少',
                      style: GoogleFonts.manrope(
                        fontSize: AppFontSize.xs,
                        fontWeight: FontWeight.w600,
                        color: AppColors.fkDanger,
                        letterSpacing: -0.1,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

class _StatusMark extends StatelessWidget {
  final bool isAvailable;
  const _StatusMark({required this.isAvailable});

  @override
  Widget build(BuildContext context) {
    if (isAvailable) {
      return Container(
        width: 24,
        height: 24,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.check_rounded, size: 14, color: Colors.white),
      );
    }
    // 缺少:白底 + 珊瑚虚线圈(设计稿 `screens-3.jsx`)。
    return FkDashedBorder(
      radius: 12,
      color: AppColors.fkDanger,
      strokeWidth: 2,
      fillColor: Colors.white,
      child: const SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: Icon(Icons.close_rounded, size: 12, color: AppColors.fkDanger),
        ),
      ),
    );
  }
}

class _AddMissingCta extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  final bool loading;
  const _AddMissingCta({
    required this.count,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '一键加购缺少的 $count 件',
      child: GestureDetector(
        onTap: loading ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryContainer,
                  ),
                )
              else
                const Icon(
                  Icons.shopping_cart_outlined,
                  size: 16,
                  color: AppColors.primaryContainer,
                ),
              const SizedBox(width: 6),
              Text(
                loading ? '正在加入…' : '一键加购缺少的 $count 件',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  final List<String> steps;
  final Set<int> completed;
  final double progress;
  final void Function(int) onToggleStep;

  const _StepsSection({
    required this.steps,
    required this.completed,
    required this.progress,
    required this.onToggleStep,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '烹饪步骤',
              style: GoogleFonts.plusJakartaSans(
                fontSize: AppFontSize.lg,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const Spacer(),
            if (steps.isNotEmpty)
              Text(
                '${completed.length}/${steps.length}',
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.sm,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
          ],
        ),
        if (steps.isNotEmpty) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.xs),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceContainer,
              color: AppColors.primary,
              minHeight: 4,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ] else
          const SizedBox(height: 10),
        ListView.separated(
          padding: EdgeInsets.zero,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: steps.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (_, index) => _StepRow(
            index: index,
            text: steps[index],
            completed: completed.contains(index),
            onTap: () => onToggleStep(index),
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String text;
  final bool completed;
  final VoidCallback onTap;

  const _StepRow({
    required this.index,
    required this.text,
    required this.completed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FkCard(
      key: ValueKey('step_$index'),
      padding: const EdgeInsets.all(AppSpacing.md),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: completed ? AppColors.primary : AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: completed
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : Text(
                    '${index + 1}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: AppFontSize.sm,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primaryContainer,
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: AnimatedDefaultTextStyle(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : AppDuration.normal,
                curve: AppMotionCurves.standard,
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.md,
                  height: 1.5,
                  color: completed
                      ? AppColors.onSurfaceVariant
                      : AppColors.onSurface,
                  decoration: completed ? TextDecoration.lineThrough : null,
                ),
                child: Text(text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「加入计划」选择器:列出今天起 7 天,点选某天即 `Navigator.pop` 回该日期。
class _PlanDayPickerSheet extends StatelessWidget {
  const _PlanDayPickerSheet({required this.today});

  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final days = List.generate(7, (i) => today.add(Duration(days: i)));
    return SafeArea(
      top: false,
      // Scrollable so a short screen (or large text scale) scrolls the 7 days
      // instead of overflowing the bottom sheet's bounded height.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                '加入哪天的计划?',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: AppFontSize.lg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                ),
              ),
            ),
            for (final day in days)
              ListTile(
                key: ValueKey('plan-day-${MealPlanEntry.dateKey(day)}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.event_outlined,
                  color: AppColors.primary,
                ),
                title: Text(
                  mealPlanDayLabel(day, today),
                  style: tt.bodyLarge?.copyWith(color: AppColors.onSurface),
                ),
                trailing: Text(
                  '${day.month}/${day.day}',
                  style: tt.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(day),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartCookingButton extends StatelessWidget {
  final VoidCallback onTap;
  const _StartCookingButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '开始烹饪',
      child: GestureDetector(
        key: const Key('recipe_start_cooking_action'),
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: AppShadows.strong,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.restaurant_menu_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 6),
              Text(
                '开始烹饪',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
