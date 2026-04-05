import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'theme/app_theme.dart';
import 'providers/navigation_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/inventory_screen.dart';
import 'screens/add_ingredient_screen.dart';
import 'screens/shopping_list_screen.dart';
import 'widgets/common/top_app_bar.dart';
import 'widgets/common/bottom_nav_bar.dart';
import 'widgets/common/search_overlay.dart';

class FreshPantryApp extends StatelessWidget {
  const FreshPantryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '食材管家',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const AppShell(),
    );
  }
}

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  static const _screens = [
    DashboardScreen(),
    InventoryScreen(),
    AddIngredientScreen(),
    ShoppingListScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navigationProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                const TopAppBar(),
                Expanded(
                  child: IndexedStack(index: currentIndex, children: _screens),
                ),
              ],
            ),
            // Search overlay on top
            const SearchOverlay(),
          ],
        ),
      ),
      extendBody: true,
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}
