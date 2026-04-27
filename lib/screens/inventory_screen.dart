import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/ingredient.dart';
import '../models/shopping_item.dart';
import '../theme/app_theme.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../screens/add_ingredient_screen.dart';
import '../widgets/inventory/ingredient_card.dart';
import '../widgets/common/category_chips.dart';
import '../widgets/common/swipe_reveal_delete_action.dart';

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  Future<void> _onRefresh() async {
    // Simulate a refresh; in a real app this would re-fetch from server
    await Future.delayed(const Duration(milliseconds: 800));
  }

  int _indexOfInventoryItem(Ingredient item) {
    return ref.read(inventoryProvider).indexOf(item);
  }

  Future<void> _editItem(Ingredient item) async {
    final index = _indexOfInventoryItem(item);
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

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「$updatedName」已更新'),
        persist: false,
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showItemActions(Ingredient item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.outline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    item.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildActionTile(
                    icon: Icons.shopping_cart_outlined,
                    label: '加入购物清单',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.pop(ctx);
                      ref
                          .read(shoppingProvider.notifier)
                          .add(
                            ShoppingItem(
                              id: 'si_${DateTime.now().millisecondsSinceEpoch}',
                              name: item.name,
                              detail: '${item.quantity} ${item.unit}',
                              category: item.category ?? '其他',
                            ),
                          );
                      ScaffoldMessenger.of(context).clearSnackBars();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已将「${item.name}」加入购物清单'),
                          persist: false,
                          backgroundColor: AppColors.primary,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      );
                    },
                  ),
                  _buildActionTile(
                    icon: Icons.edit_outlined,
                    label: '编辑',
                    color: AppColors.onSurface,
                    onTap: () {
                      Navigator.pop(ctx);
                      _editItem(item);
                    },
                  ),
                  _buildActionTile(
                    icon: Icons.delete_outline,
                    label: '删除',
                    color: AppColors.error,
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(item);
                    },
                  ),
                ],
              ),
            ),
          ),
    );
  }

  void _confirmDelete(Ingredient item) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Text(
              '删除食材',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
            ),
            content: Text(
              '确定要删除「${item.name}」吗？此操作不可撤销。',
              style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  '取消',
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _deleteItem(item);
                },
                child: Text(
                  '删除',
                  style: GoogleFonts.manrope(
                    color: AppColors.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
    );
  }

  void _deleteItem(Ingredient item) {
    final index = _indexOfInventoryItem(item);
    if (index == -1) return;

    ref.read(inventoryProvider.notifier).remove(index);
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('「${item.name}」已删除'),
        persist: false,
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: '撤销',
          textColor: AppColors.onError,
          onPressed: () {
            ref.read(inventoryProvider.notifier).add(item);
          },
        ),
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: GoogleFonts.manrope(fontWeight: FontWeight.w600, color: color),
      ),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final filteredItems = ref.watch(filteredByCategoryProvider);

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '食材库存',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: AppColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '管理您精心策划的新鲜食材收藏。',
                      style: GoogleFonts.manrope(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Category filters
            SliverToBoxAdapter(
              child: CategoryChips(
                categories: categories,
                leadingCategories: const [inventoryFilterNotFresh],
                selectedCategory: selectedCategory,
                onSelected: (category) {
                  ref.read(selectedCategoryProvider.notifier).state = category;
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            // Ingredient list
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              sliver:
                  filteredItems.isEmpty
                      ? SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 48),
                            child: Text(
                              '该分类下暂无食材',
                              style: GoogleFonts.manrope(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      )
                      : SliverList.separated(
                        itemCount: filteredItems.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          final item = filteredItems[index];
                          return SwipeRevealDeleteAction(
                            key: ValueKey('inv_swipe_${item.name}_$index'),
                            deleteButtonKey: ValueKey(
                              'inventory_swipe_delete_${item.name}_$index',
                            ),
                            onDelete: () => _deleteItem(item),
                            child: IngredientCard(
                              ingredient: item,
                              onTap: () => _showItemActions(item),
                              onBuyAgain: () {
                                ref
                                    .read(shoppingProvider.notifier)
                                    .add(
                                      ShoppingItem(
                                        id:
                                            'si_${DateTime.now().millisecondsSinceEpoch}',
                                        name: item.name,
                                        detail: '${item.quantity} ${item.unit}',
                                        category: item.category ?? '其他',
                                      ),
                                    );
                                ScaffoldMessenger.of(context).clearSnackBars();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('已将「${item.name}」加入购物清单'),
                                    persist: false,
                                    backgroundColor: AppColors.primary,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }
}
