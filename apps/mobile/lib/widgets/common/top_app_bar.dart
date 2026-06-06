import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../../providers/navigation_provider.dart';
import '../../screens/settings_screen.dart';
import '../../utils/page_transitions.dart';
import '../../household/household_session_controller.dart';

/// 首页 Header 固定高度 — Dashboard hero 用它换算顶部留白,使蓝色铺到状态栏
/// 后面时问候文案不会被浮在上方的 Header 压住。
const double kTopAppBarHeight = 64;

class TopAppBar extends ConsumerWidget {
  const TopAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasInvite = ref.watch(
      householdSessionControllerProvider.select(
        (s) => s.pendingInvitePreviews.isNotEmpty,
      ),
    );
    return SizedBox(
      height: kTopAppBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    semanticLabel: '食材管家应用图标',
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(Icons.error, size: 40);
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '食材管家',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: AppFontSize.xl,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                      ),
                      tooltip: '设置',
                      onPressed: () {
                        Navigator.of(context).push(
                          fkRoute<void>(builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                    if (hasInvite)
                      Positioned(
                        right: 8,
                        top: 10,
                        child: IgnorePointer(
                          child: Container(
                            key: const ValueKey('settings_invite_badge'),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.fkAlert,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white),
                  tooltip: '搜索',
                  onPressed: () {
                    ref.read(searchActiveProvider.notifier).state = true;
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
