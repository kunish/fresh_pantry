import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../providers/inventory_provider.dart';
import '../widgets/ingredient_card.dart';
import '../widgets/common/category_chips.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);
    final filteredItems = ref.watch(filteredByCategoryProvider);

    return CustomScrollView(
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
                  style: GoogleFonts.manrope(color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
        // Category filters — using the common CategoryChips widget
        SliverToBoxAdapter(
          child: CategoryChips(
            categories: categories,
            selectedCategory: selectedCategory,
            onSelected: (category) {
              ref.read(selectedCategoryProvider.notifier).state = category;
            },
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
        // Ingredient list — driven by filtered provider
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          sliver: filteredItems.isEmpty
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
                  itemBuilder: (context, index) =>
                      IngredientCard(ingredient: filteredItems[index]),
                ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }
}
