import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/recipe_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/recipe_card.dart';
import '../widgets/shared/fk_icon_button.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'recipe_detail_screen.dart';

/// FreshKeeper 菜谱 tab — 设计稿 `screens-3.jsx::RecipesScreen`。
///
/// 3-tab segmented(用临期 / 现有食材 / 探索)+ 时间筛选(不限 / ≤15 / ≤30 分钟)。
/// "用临期" 顶部展示橙黄 banner 提醒优先使用临期食材的数量。
enum _RecipeTab { expiring, available, explore }

enum _TimeFilter { all, fast15, fast30 }

class RecipesScreen extends ConsumerStatefulWidget {
  const RecipesScreen({super.key});

  @override
  ConsumerState<RecipesScreen> createState() => _RecipesScreenState();
}

class _RecipesScreenState extends ConsumerState<RecipesScreen> {
  _RecipeTab _tab = _RecipeTab.expiring;
  _TimeFilter _time = _TimeFilter.all;

  @override
  Widget build(BuildContext context) {
    final inventory = ref.watch(inventoryProvider);
    final recommended = ref.watch(recommendedRecipesProvider);
    final allAsync = ref.watch(recipesProvider);

    final all = allAsync.maybeWhen(
      data: (data) => data,
      orElse: () => recommended,
    );

    final expiringNames = _expiringIngredientNames(inventory);
    final expiringRecipes = recommended
        .where(
          (r) => r.ingredients.any(
            (ing) => expiringNames.any(
              (name) =>
                  name.contains(ing.name.toLowerCase()) ||
                  ing.name.toLowerCase().contains(name),
            ),
          ),
        )
        .toList();

    final list = switch (_tab) {
      _RecipeTab.expiring => expiringRecipes,
      _RecipeTab.available => recommended,
      _RecipeTab.explore => all,
    };

    final filtered = list.where((r) {
      return switch (_time) {
        _TimeFilter.all => true,
        _TimeFilter.fast15 => r.cookingMinutes <= 15,
        _TimeFilter.fast30 => r.cookingMinutes <= 30,
      };
    }).toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FkTopBar(
            title: '智能菜谱',
            subtitle: '基于你的冰箱推荐',
            actions: [
              FkIconButton(
                onTap: () {},
                child: const Icon(Icons.search_rounded, size: 18),
              ),
            ],
          ),
          _TabRow(
            selected: _tab,
            onSelect: (t) => setState(() => _tab = t),
          ),
          _TimeFilterRow(
            selected: _time,
            onSelect: (t) => setState(() => _time = t),
          ),
          if (_tab == _RecipeTab.expiring && expiringRecipes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
              child: _ExpiringBanner(count: expiringNames.length),
            ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(tab: _tab)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 120),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final recipe = filtered[i];
                      final matched =
                          matchedIngredientCount(inventory, recipe);
                      final useExpiring = _tab == _RecipeTab.expiring;
                      return RecipeCard(
                        recipe: recipe,
                        matchedCount: matched,
                        useExpiring: useExpiring,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                RecipeDetailScreen(recipe: recipe),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 名称小写归一化后的 expiring/expired 食材集合 — 用作"用临期"tab 的匹配键。
  Set<String> _expiringIngredientNames(List<Ingredient> inventory) {
    return inventory
        .where(
          (i) =>
              i.state == FreshnessState.expiringSoon ||
              i.state == FreshnessState.expired,
        )
        .map((i) => i.name.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
  }
}

class _TabRow extends StatelessWidget {
  final _RecipeTab selected;
  final void Function(_RecipeTab) onSelect;
  const _TabRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final tabs = <(_RecipeTab, String, IconData)>[
      (_RecipeTab.expiring, '用临期', Icons.local_fire_department_rounded),
      (_RecipeTab.available, '现有食材', Icons.eco_rounded),
      (_RecipeTab.explore, '探索', Icons.menu_book_rounded),
    ];
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair, width: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          for (final (value, label, icon) in tabs)
            Expanded(child: _TabButton(
              icon: icon,
              label: label,
              active: value == selected,
              onTap: () => onSelect(value),
            )),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary : AppColors.onSurfaceVariant;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 10, 0, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (active)
            Positioned(
              left: 24,
              right: 24,
              bottom: 0,
              child: Container(
                height: 2.5,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeFilterRow extends StatelessWidget {
  final _TimeFilter selected;
  final void Function(_TimeFilter) onSelect;
  const _TimeFilterRow({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final filters = <(_TimeFilter, String)>[
      (_TimeFilter.all, '不限时间'),
      (_TimeFilter.fast15, '⏱ 15 分钟内'),
      (_TimeFilter.fast30, '⏱ 30 分钟内'),
    ];
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label) = filters[i];
          final active = value == selected;
          return GestureDetector(
            onTap: () => onSelect(value),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.hair,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
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

class _ExpiringBanner extends StatelessWidget {
  final int count;
  const _ExpiringBanner({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.fkWarnSoft,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 16,
            color: AppColors.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '优先使用 $count 件临期食材',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final _RecipeTab tab;
  const _EmptyState({required this.tab});

  @override
  Widget build(BuildContext context) {
    final msg = switch (tab) {
      _RecipeTab.expiring => '没有临期食材,先去添加几样吧',
      _RecipeTab.available => '冰箱里加点食材,菜谱就来啦',
      _RecipeTab.explore => '暂无可探索的菜谱',
    };
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Text(
          msg,
          style: GoogleFonts.manrope(
            fontSize: 14,
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
