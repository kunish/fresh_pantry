import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ingredient.dart';
import '../models/recipe.dart';
import '../models/shopping_item.dart';
import '../data/food_knowledge.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/shared/pill_chip.dart';
import '../widgets/shared/recipe_image.dart';

class RecipeDetailScreen extends ConsumerStatefulWidget {
  final Recipe recipe;
  final bool isCustomRecipe;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const RecipeDetailScreen({
    super.key,
    required this.recipe,
    this.isCustomRecipe = false,
    this.onEdit,
    this.onDelete,
  });

  @override
  ConsumerState<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends ConsumerState<RecipeDetailScreen> {
  final Set<int> _completedSteps = <int>{};

  @override
  void didUpdateWidget(covariant RecipeDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.recipe.id != widget.recipe.id ||
        !listEquals(oldWidget.recipe.steps, widget.recipe.steps)) {
      _completedSteps.clear();
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
    var addedCount = 0;
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

    if (!mounted) return;

    showAppSnackBar(
      context,
      addedCount == 0 ? '缺失食材已在购物清单中' : '已将 $addedCount 个食材加入购物清单',
      backgroundColor:
          addedCount == 0 ? AppColors.tertiary : AppColors.primary,
    );
  }

  List<RecipeIngredient> _getMissingIngredients(
    List<Ingredient> inventory,
    Recipe recipe,
  ) {
    final inventoryNames =
        inventory.map((i) => _normalizedIngredientName(i.name)).toSet();
    return recipe.ingredients.where((ing) {
      return !_ingredientNameMatchesInventory(ing.name, inventoryNames);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final matched = matchedIngredientCount(inventory, widget.recipe);
    final missing = _getMissingIngredients(inventory, widget.recipe);
    final stepProgress =
        widget.recipe.steps.isEmpty
            ? 0.0
            : _completedSteps.length / widget.recipe.steps.length;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: CustomScrollView(
        slivers: [
          // Hero image app bar
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.onSurface,
            actions: [
              if (widget.isCustomRecipe && widget.onEdit != null)
                IconButton(
                  tooltip: '编辑食谱',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: widget.onEdit,
                ),
              if (widget.isCustomRecipe && widget.onDelete != null)
                IconButton(
                  tooltip: '删除食谱',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  RecipeImage(
                    imageSource: widget.recipe.imageUrl,
                    fit: BoxFit.cover,
                    semanticLabel: widget.recipe.name,
                    fallback: Container(
                      color: AppColors.surfaceContainerLow,
                      child: Semantics(
                        label: widget.recipe.name,
                        image: true,
                        child: const Icon(Icons.restaurant, size: 64),
                      ),
                    ),
                  ),
                  // 顶部 scrim：保证深色 status bar 图标和 leading/actions
                  // 在任何颜色的封面图（红烧肉、巧克力等深色食物）上都可读。
                  Align(
                    alignment: Alignment.topCenter,
                    child: IgnorePointer(
                      child: SizedBox(
                        height:
                            MediaQuery.of(context).padding.top + kToolbarHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppColors.surface.withValues(alpha: 0.55),
                                AppColors.surface.withValues(alpha: 0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Title
                Text(
                  widget.recipe.name,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.xxl,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  widget.recipe.description,
                  style: GoogleFonts.manrope(
                    fontSize: AppFontSize.md,
                    color: AppColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Meta chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    PillChip(
                      icon: Icons.timer_outlined,
                      label: '${widget.recipe.cookingMinutes}分钟',
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      iconForegroundColor: AppColors.primary,
                    ),
                    PillChip(
                      icon: Icons.local_fire_department_outlined,
                      label: widget.recipe.difficultyLabel,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      iconForegroundColor: AppColors.primary,
                    ),
                    PillChip(
                      icon: Icons.checklist,
                      label: '$matched/${widget.recipe.ingredients.length} 食材已备',
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      iconForegroundColor: AppColors.primary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.huge),

                // Missing ingredients action
                if (missing.isNotEmpty) ...[
                  Semantics(
                    button: true,
                    label: '一键补齐食材',
                    child: GestureDetector(
                      onTap: () => _addMissingToCart(missing),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: const Icon(
                                Icons.add_shopping_cart,
                                color: AppColors.onPrimary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.lg),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '一键补齐食材',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onPrimaryContainer,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    '将 ${missing.length} 个缺失食材加入购物清单',
                                    style: GoogleFonts.manrope(
                                      fontSize: AppFontSize.sm,
                                      color: AppColors.onPrimaryContainer
                                          .withValues(alpha: 0.8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward,
                              color: AppColors.onPrimaryContainer,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.huge),
                ],

                // Ingredients
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '所需食材',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: AppFontSize.xl,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.recipe.ingredients.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primaryFixed,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '$matched/${widget.recipe.ingredients.length}',
                          style: GoogleFonts.manrope(
                            fontSize: AppFontSize.xs,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                ..._buildIngredientsList(inventory, widget.recipe),
                const SizedBox(height: AppSpacing.huge),

                // Steps with progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '烹饪步骤',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: AppFontSize.xl,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (widget.recipe.steps.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color:
                              stepProgress >= 1.0
                                  ? AppColors.primaryFixed
                                  : AppColors.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(
                          '${_completedSteps.length}/${widget.recipe.steps.length}',
                          style: GoogleFonts.manrope(
                            fontSize: AppFontSize.xs,
                            fontWeight: FontWeight.w700,
                            color:
                                stepProgress >= 1.0
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
                if (widget.recipe.steps.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    child: LinearProgressIndicator(
                      value: stepProgress,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      color: AppColors.primary,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                ] else
                  const SizedBox(height: AppSpacing.md),
                for (final (index, step) in widget.recipe.steps.indexed)
                  _buildStepRow(index, step),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepRow(int index, String step) {
    final isCompleted = _completedSteps.contains(index);
    return Padding(
      key: ValueKey('step_$index'),
      padding: const EdgeInsets.only(bottom: 16),
      child: GestureDetector(
        onTap: () => _toggleStep(index),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: isCompleted ? AppColors.primary : AppColors.primaryFixed,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              alignment: Alignment.center,
              child:
                  isCompleted
                      ? const Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.onPrimary,
                      )
                      : Text(
                        '${index + 1}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: AppFontSize.sm,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                step,
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.md,
                  color:
                      isCompleted
                          ? AppColors.onSurfaceVariant
                          : AppColors.onSurface,
                  height: 1.5,
                  decoration: isCompleted ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildIngredientsList(
    List<Ingredient> inventory,
    Recipe recipe,
  ) {
    final inventoryNames =
        inventory.map((i) => _normalizedIngredientName(i.name)).toSet();
    return [
      for (final (index, ingredient) in recipe.ingredients.indexed)
        _buildIngredientRow(index, ingredient, inventoryNames),
    ];
  }

  Widget _buildIngredientRow(
    int index,
    RecipeIngredient ingredient,
    Set<String> inventoryNames,
  ) {
    final available = _ingredientNameMatchesInventory(
      ingredient.name,
      inventoryNames,
    );
    return Padding(
      key: ValueKey('ingredient_$index'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(
            available ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: available ? AppColors.primary : AppColors.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '${ingredient.name} (${ingredient.amount})',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.md,
                color:
                    available
                        ? AppColors.onSurface
                        : AppColors.onSurfaceVariant,
                decoration: available ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          if (available)
            Text(
              '库存中',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.sm,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  bool _ingredientNameMatchesInventory(
    String ingredientName,
    Set<String> inventoryNames,
  ) {
    final normalizedIngredientName = _normalizedIngredientName(ingredientName);
    if (normalizedIngredientName.isEmpty) return false;

    return inventoryNames.any(
      (name) =>
          name.contains(normalizedIngredientName) ||
          normalizedIngredientName.contains(name),
    );
  }

  String _normalizedIngredientName(String name) {
    return name.trim().toLowerCase();
  }

}
