import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../theme/app_theme.dart';
import '../theme/fk_category_palette.dart';
import '../utils/app_snackbar.dart';
import '../utils/storage_labels.dart';
import '../widgets/shared/cat_icon.dart';
import '../widgets/shared/category_icon.dart';
import '../widgets/shared/fk_card.dart';
import '../widgets/shared/fk_pill.dart';
import '../widgets/shared/fk_top_bar.dart';
import 'ingredient_detail_screen.dart';
import 'settings_screen.dart';

/// FreshKeeper 临期提醒页 — 设计稿 `screens-2.jsx::ExpiringScreen`。
///
/// 按剩余天数分组(已过期 / 即将过期)展示。每条 row 含 CatIcon + 名称 +
/// qty/zone + status pill + 3 个 mini action(用了 / 加购 / 菜谱)。顶部
/// 提醒设置入口 push 进入 [SettingsScreen]。
class ExpiringScreen extends ConsumerWidget {
  const ExpiringScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expiring = ref.watch(expiringItemsProvider);
    final expired = expiring
        .where((i) => i.state == FreshnessState.expired)
        .toList();
    final soon = expiring
        .where((i) => i.state == FreshnessState.expiringSoon)
        .toList();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: [
            FkTopBar(
              title: '临期提醒',
              subtitle: '按状态分组 · 优先处理高亮项',
              onBack: () => Navigator.of(context).maybePop(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: _RemindShortcut(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (expired.isEmpty && soon.isEmpty)
              const _EmptyState()
            else ...[
              if (expired.isNotEmpty)
                _Group(
                  title: '已过期 / 今天到期',
                  count: expired.length,
                  dotColor: AppColors.fkDanger,
                  items: expired,
                ),
              if (soon.isNotEmpty)
                _Group(
                  title: '即将过期',
                  count: soon.length,
                  dotColor: AppColors.fkWarn,
                  items: soon,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RemindShortcut extends StatelessWidget {
  final VoidCallback onTap;
  const _RemindShortcut({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FkCard(
      backgroundColor: AppColors.primarySoft,
      padding: const EdgeInsets.all(14),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.notifications_outlined,
              size: 18,
              color: AppColors.primaryContainer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '提醒已开启',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryContainer,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '提前 1 天 · 每日 9:00 提醒',
                  style: GoogleFonts.manrope(
                    fontSize: 11,
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

class _Group extends ConsumerWidget {
  final String title;
  final int count;
  final Color dotColor;
  final List<Ingredient> items;

  const _Group({
    required this.title,
    required this.count,
    required this.dotColor,
    required this.items,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count 件',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    color: AppColors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          FkCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++)
                  _ExpiringRow(
                    item: items[i],
                    isLast: i == items.length - 1,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiringRow extends ConsumerWidget {
  final Ingredient item;
  final bool isLast;
  const _ExpiringRow({required this.item, required this.isLast});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catId = fkCategoryIdFor(item.category);
    final palette = FkCategoryPalette.of(catId);
    final isExpired = item.state == FreshnessState.expired;
    final pillBg = isExpired ? AppColors.fkDanger : AppColors.fkWarnSoft;
    final pillFg = isExpired ? Colors.white : AppColors.onSecondaryContainer;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.hair, width: 0.5),
              ),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => IngredientDetailScreen(ingredient: item),
              ),
            ),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: palette.tint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: CatIcon(
                    category: catId,
                    size: 28,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${item.quantity}${item.unit} · ${storageLabelFor(item.storage)}',
                        style: GoogleFonts.manrope(
                          fontSize: 11,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.expiryLabel != null)
                  FkPill(
                    label: item.expiryLabel!,
                    backgroundColor: pillBg,
                    foregroundColor: pillFg,
                    sm: true,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Row(
              children: [
                _MiniBtn(
                  icon: Icons.check_rounded,
                  label: '用了',
                  soft: true,
                  onTap: () => _markUsed(context, ref),
                ),
                const SizedBox(width: 8),
                _MiniBtn(
                  icon: Icons.shopping_cart_outlined,
                  label: '加购',
                  onTap: () => _addToShopping(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _markUsed(BuildContext context, WidgetRef ref) {
    final index = inventoryIndexOf(ref.read(inventoryProvider), item);
    if (index == -1) return;
    ref.read(inventoryProvider.notifier).remove(index);
    showAppSnackBar(
      context,
      '「${item.name}」已标记使用',
      backgroundColor: AppColors.primary,
    );
  }

  Future<void> _addToShopping(BuildContext context, WidgetRef ref) async {
    final added = await ref
        .read(shoppingProvider.notifier)
        .addFromIngredient(item);
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      added ? '已加入清单 · ${item.name}' : '「${item.name}」已在购物清单中',
      backgroundColor: added ? AppColors.primary : AppColors.tertiary,
    );
  }
}

class _MiniBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool soft;
  final VoidCallback onTap;
  const _MiniBtn({
    required this.icon,
    required this.label,
    this.soft = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = soft ? AppColors.primarySoft : AppColors.surfaceContainer;
    final fg = soft ? AppColors.primaryContainer : AppColors.onSurface;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 3),
            Text(
              label,
              style: GoogleFonts.manrope(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 60),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 32,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '没有临期食材',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '冰箱状态健康,继续保持!',
              style: GoogleFonts.manrope(
                fontSize: 12,
                color: AppColors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
