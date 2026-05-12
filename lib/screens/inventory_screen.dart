import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/food_categories.dart';
import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../screens/ingredient_detail_screen.dart';
import '../theme/app_theme.dart';
import '../utils/app_snackbar.dart';
import '../widgets/inventory/ingredient_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_top_bar.dart';

/// FreshKeeper 食材库 — 设计稿 `screens-2.jsx::IngredientsScreen`。
///
/// FK top bar + 搜索框 + 分类 chip 横滚(全部 / 5 大类)+ 状态 chip 横滚(全部 /
/// 不新鲜)+ 2-col grid IngredientCard。
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() async {
    await Future.delayed(const Duration(milliseconds: 600));
  }

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

  Future<void> _openItemDetail(Ingredient item) async {
    final result = await Navigator.of(context).push<IngredientDetailResult>(
      MaterialPageRoute(
        builder: (_) => IngredientDetailScreen(ingredient: item),
      ),
    );
    if (!mounted || result == null) return;
    switch (result.type) {
      case IngredientDetailResultType.updated:
        final name = result.name;
        if (name != null) {
          showAppSnackBar(
            context,
            '「$name」已更新',
            backgroundColor: AppColors.primary,
          );
        }
      case IngredientDetailResultType.deleted:
        final deletedItem = result.item;
        final index = result.index;
        if (deletedItem != null && index != null) {
          showAppSnackBar(
            context,
            '「${deletedItem.name}」已删除',
            backgroundColor: AppColors.error,
            actionLabel: '撤销',
            actionTextColor: AppColors.onError,
            onAction: () {
              ref
                  .read(inventoryProvider.notifier)
                  .insertAt(index, deletedItem);
            },
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final filteredByCategory = ref.watch(filteredByCategoryProvider);

    // Apply free-text search on top of the category filter.
    final items = _query.isEmpty
        ? filteredByCategory
        : filteredByCategory
            .where(
              (i) => i.name.toLowerCase().contains(_query.toLowerCase()),
            )
            .toList();

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
              child: SafeArea(
                bottom: false,
                child: FkTopBar(
                  title: '我的食材',
                  subtitle: '共 ${inventory.length} 件',
                  actions: [
                    FkIconButton(
                      child: const Icon(Icons.tune_rounded),
                      onTap: () {},
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(child: _SearchField(controller: _searchCtrl, onChanged: (v) {
              setState(() => _query = v);
            })),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child: _CategoryChipRow(
                selected: selectedCategory,
                inventory: inventory,
                onSelect: (cat) =>
                    ref.read(selectedCategoryProvider.notifier).state = cat,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 10)),
            if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Center(
                    child: Text(
                      _query.isNotEmpty ? '没有找到「$_query」' : '该分类下暂无食材',
                      style: GoogleFonts.manrope(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.85,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final item = items[index];
                    return IngredientCard(
                      key: ValueKey('inv_${item.name}_$index'),
                      ingredient: item,
                      onTap: () => _openItemDetail(item),
                      onBuyAgain: () => _addToShoppingList(item),
                    );
                  }, childCount: items.length),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surfaceContainer,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              size: 18,
              color: AppColors.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  color: AppColors.onSurface,
                ),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  filled: false,
                  hintText: '搜索食材',
                  hintStyle: GoogleFonts.manrope(
                    fontSize: 14,
                    color: AppColors.onSurfaceVariant,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChipRow extends StatelessWidget {
  final String selected;
  final List<Ingredient> inventory;
  final void Function(String) onSelect;
  const _CategoryChipRow({
    required this.selected,
    required this.inventory,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final categoryCounts = <String, int>{};
    for (final item in inventory) {
      final cat = FoodCategories.dropdownValue(item.category);
      categoryCounts[cat] = (categoryCounts[cat] ?? 0) + 1;
    }

    final chips = <_Chip>[
      _Chip(label: '全部', value: inventoryFilterAll, count: inventory.length),
      _Chip(
        label: '不新鲜',
        value: inventoryFilterNotFresh,
        count: inventory
            .where(
              (i) =>
                  i.state == FreshnessState.expiringSoon ||
                  i.state == FreshnessState.expired,
            )
            .length,
      ),
      ...FoodCategories.values.map(
        (cat) => _Chip(
          label: cat,
          value: cat,
          count: categoryCounts[cat] ?? 0,
        ),
      ),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = chips[i];
          final active = c.value == selected;
          return GestureDetector(
            onTap: () => onSelect(c.value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.hair,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                c.count > 0 ? '${c.label} · ${c.count}' : c.label,
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Chip {
  final String label;
  final String value;
  final int count;
  _Chip({required this.label, required this.value, required this.count});
}
