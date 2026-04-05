import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../models/ingredient.dart';
import '../providers/inventory_provider.dart';
import '../providers/shopping_provider.dart';
import '../providers/navigation_provider.dart';
import '../data/mock_data.dart';
import '../widgets/dashboard/stat_card.dart';
import '../widgets/dashboard/alert_card.dart';
import '../widgets/dashboard/quick_action_card.dart';
import '../widgets/dashboard/storage_summary_card.dart';
import '../widgets/dashboard/recent_addition_item.dart';
import '../widgets/dashboard/curators_tip_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGreeting(ref),
          const SizedBox(height: 32),
          _buildUrgentAndActions(ref),
          const SizedBox(height: 40),
          _buildStorageSummary(),
          const SizedBox(height: 40),
          _buildRecentAndTip(ref),
        ],
      ),
    );
  }

  Widget _buildGreeting(WidgetRef ref) {
    final stats = ref.watch(statCountsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '早安，主厨。',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '您的食材库已备齐84%，本周食材已精心策划。',
          style: GoogleFonts.manrope(
            fontSize: 16,
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        // Stats row — driven by providers
        Row(
          children: [
            StatCard(value: '${stats.total}', label: '种食材'),
            const SizedBox(width: 16),
            StatCard(
              value: '${stats.expiringSoon}',
              label: '即将过期',
              isWarning: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUrgentAndActions(WidgetRef ref) {
    final expiringItems = ref.watch(expiringItemsProvider);
    final uncheckedCount = ref.watch(uncheckedCountProvider);

    return Column(
      children: [
        // Urgent Attention
        Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.priority_high, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Text(
                    '紧急关注',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Alert items from provider
              ...expiringItems
                  .take(2)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: AlertCard(
                        icon: _iconForCategory(item.category),
                        iconColor: item.state == FreshnessState.expired
                            ? AppColors.secondary
                            : AppColors.primary,
                        name: item.name,
                        subtitle: item.expiryLabel ?? '即将过期',
                        badge: item.state == FreshnessState.expired
                            ? '今天'
                            : '48H',
                        badgeBg: item.state == FreshnessState.expired
                            ? AppColors.secondaryContainer
                            : AppColors.surfaceContainerHigh,
                        badgeText: item.state == FreshnessState.expired
                            ? AppColors.onSecondaryContainer
                            : AppColors.onSurfaceVariant,
                      ),
                    ),
                  ),
              if (expiringItems.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '暂无需要紧急关注的食材',
                    style: GoogleFonts.manrope(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryContainer],
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '食谱推荐',
                      style: GoogleFonts.manrope(
                        fontWeight: FontWeight.w700,
                        color: AppColors.onPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward,
                      color: AppColors.onPrimary,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Quick Actions — navigate via provider
        Row(
          children: [
            Expanded(
              child: QuickActionCard(
                icon: Icons.add_circle,
                title: '添加新食材',
                subtitle: '扫码或手动录入',
                backgroundColor: AppColors.primary,
                contentColor: AppColors.onPrimary,
                onTap: () {
                  ref.read(navigationProvider.notifier).state = 2;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: QuickActionCard(
                icon: Icons.shopping_basket,
                title: '购物清单',
                subtitle: '还需$uncheckedCount件',
                backgroundColor: AppColors.tertiaryFixedDim,
                contentColor: const Color(0xFF251A00),
                onTap: () {
                  ref.read(navigationProvider.notifier).state = 3;
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStorageSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '存储概况',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            Text(
              '查看全部',
              style: GoogleFonts.manrope(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        ...MockData.storageAreas.map(
          (area) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: StorageSummaryCard(area: area),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentAndTip(WidgetRef ref) {
    final recentItems = ref.watch(recentAdditionsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近添加',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 16),
        ...recentItems.map((item) => RecentAdditionItem(item: item)),
        const SizedBox(height: 24),
        const CuratorsTipCard(tip: '您的牛油果明天将达到最佳成熟度，正好可以做上周二收藏的牛油果酱食谱。'),
      ],
    );
  }

  /// Map category string to an appropriate icon
  IconData _iconForCategory(String? category) {
    return switch (category) {
      '蔬菜' => Icons.eco_outlined,
      '蛋白质' => Icons.egg_outlined,
      '乳制品' => Icons.water_drop_outlined,
      '谷物' => Icons.bakery_dining_outlined,
      _ => Icons.restaurant_outlined,
    };
  }
}
