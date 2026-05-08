import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_details.dart';
import '../models/ingredient.dart';
import '../providers/food_details_provider.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_dialog.dart';
import '../utils/app_snackbar.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/pill_chip.dart';
import '../widgets/shared/recipe_image.dart';
import 'add_ingredient_screen.dart';

enum IngredientDetailResultType { updated, deleted }

class IngredientDetailResult {
  const IngredientDetailResult._({
    required this.type,
    this.name,
    this.item,
    this.index,
  });

  final IngredientDetailResultType type;
  final String? name;
  final Ingredient? item;
  final int? index;

  factory IngredientDetailResult.updated(String name) {
    return IngredientDetailResult._(
      type: IngredientDetailResultType.updated,
      name: name,
    );
  }

  factory IngredientDetailResult.deleted(Ingredient item, int index) {
    return IngredientDetailResult._(
      type: IngredientDetailResultType.deleted,
      item: item,
      index: index,
    );
  }
}

class IngredientDetailScreen extends ConsumerStatefulWidget {
  const IngredientDetailScreen({super.key, required this.ingredient});

  final Ingredient ingredient;

  @override
  ConsumerState<IngredientDetailScreen> createState() =>
      _IngredientDetailScreenState();
}

class _IngredientDetailScreenState
    extends ConsumerState<IngredientDetailScreen> {
  Future<void> _addToShoppingList(Ingredient item) async {
    final added = await ref
        .read(shoppingProvider.notifier)
        .addFromIngredient(item);
    if (!mounted) return;
    showAppSnackBar(
      context,
      added ? '已将「${item.name}」加入购物清单' : '「${item.name}」已在购物清单中',
      backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    );
  }

  Future<void> _editItem(Ingredient item) async {
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
    if (index == -1) return;

    final updatedName = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder:
            (_) => Scaffold(
              backgroundColor: AppColors.surface,
              body: SafeArea(
                child: AddIngredientScreen(
                  initialIngredient: item,
                  inventoryIndex: index,
                ),
              ),
            ),
      ),
    );
    if (!mounted || updatedName == null) return;
    Navigator.of(context).pop(IngredientDetailResult.updated(updatedName));
  }

  Future<void> _confirmDelete(Ingredient item) async {
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
    if (index == -1) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: '删除食材',
      content: '确定要删除「${item.name}」吗？此操作不可撤销。',
      confirmLabel: '删除',
      isDestructive: true,
    );
    if (!mounted || !confirmed) return;

    ref.read(inventoryProvider.notifier).remove(index);
    Navigator.of(context).pop(IngredientDetailResult.deleted(item, index));
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final index = inventoryIndexOf(inventory, widget.ingredient);
    final item = index == -1 ? widget.ingredient : inventory[index];
    final isInventoryItem = index != -1;
    final detailsAsync = ref.watch(foodDetailsProvider(item));

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('食材详情'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
      ),
      body: detailsAsync.when(
        data: (details) => _buildDetails(item, details),
        loading:
            () => const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
        error: (_, _) => _buildDetails(item, fallbackFoodDetailsFor(item)),
      ),
      bottomNavigationBar: _ActionBar(
        onAddToShopping: () => _addToShoppingList(item),
        onEdit: () => _editItem(item),
        onDelete: () => _confirmDelete(item),
        showInventoryActions: isInventoryItem,
      ),
    );
  }

  Widget _buildDetails(Ingredient item, FoodDetails details) {
    final imageSource =
        details.imageUrl?.trim().isNotEmpty == true
            ? details.imageUrl
            : item.imageUrl.trim().isNotEmpty
            ? item.imageUrl
            : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, AppSpacing.huge),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Container(
            height: 220,
            width: double.infinity,
            color: AppColors.surfaceContainerLow,
            child: RecipeImage(
              imageSource: imageSource,
              fit: BoxFit.cover,
              fallback: Center(
                child: CategoryIconAvatar(
                  category: details.category,
                  size: 120,
                  iconSize: 52,
                  borderRadius: 20,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),
        Text(
          details.displayName,
          style: GoogleFonts.plusJakartaSans(
            fontSize: AppFontSize.xxxl,
            fontWeight: FontWeight.w800,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          details.description,
          style: GoogleFonts.manrope(
            fontSize: AppFontSize.md,
            height: 1.5,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            PillChip(
              label: '分类：${details.category}',
              backgroundColor: AppColors.surfaceContainerHigh,
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w700,
            ),
            PillChip(
              label: '建议存放：${storageLabelFor(details.storage)}',
              backgroundColor: AppColors.surfaceContainerHigh,
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w700,
            ),
            if (details.shelfLifeDays != null)
              PillChip(
                label: '保质期建议：${details.shelfLifeDays}天',
                backgroundColor: AppColors.surfaceContainerHigh,
                fontSize: AppFontSize.sm,
                fontWeight: FontWeight.w700,
              ),
            PillChip(
              label: '来源：${details.source}',
              backgroundColor: AppColors.surfaceContainerHigh,
              fontSize: AppFontSize.sm,
              fontWeight: FontWeight.w700,
            ),
          ],
        ),
      ],
    );
  }

}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.onAddToShopping,
    required this.onEdit,
    required this.onDelete,
    required this.showInventoryActions,
  });

  final VoidCallback onAddToShopping;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool showInventoryActions;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.outlineVariant)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final addButton = FilledButton.icon(
              onPressed: onAddToShopping,
              icon: const Icon(Icons.shopping_cart_outlined),
              label: const Text('加入购物清单'),
            );

            if (!showInventoryActions) {
              return SizedBox(width: double.infinity, child: addButton);
            }

            final secondaryActions = Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined),
                    label: const _ActionLabel('编辑'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const _ActionLabel('删除'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                      minimumSize: const Size(0, 48),
                    ),
                  ),
                ),
              ],
            );

            if (constraints.maxWidth < 360) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(width: double.infinity, child: addButton),
                  const SizedBox(height: AppSpacing.sm),
                  secondaryActions,
                ],
              );
            }

            return Row(
              children: [
                Expanded(child: addButton),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(width: 184, child: secondaryActions),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  const _ActionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}

