import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_card.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'recipe_detail_screen.dart';

/// FreshKeeper 菜谱 tab。Phase 4 占位实现 — 展示基于库存的推荐菜谱列表。
/// Phase 7 会重做为 3-tab segmented(用临期 / 现有食材 / 探索)+ 时间筛选 +
/// 横向 hero 卡片(设计稿 `screens-3.jsx::RecipesScreen`)。
class RecipesScreen extends ConsumerWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recipes = ref.watch(recommendedRecipesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FkTopBar(title: '智能菜谱', subtitle: '基于你的冰箱推荐'),
        Expanded(
          child: recipes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      '冰箱里加点食材,菜谱就来啦',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        color: AppColors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
                  itemCount: recipes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final recipe = recipes[i];
                    return RecipeCard(
                      recipe: recipe,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecipeDetailScreen(recipe: recipe),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
