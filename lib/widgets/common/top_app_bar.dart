import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../data/mock_data.dart';
import '../../theme/app_theme.dart';
import '../../providers/navigation_provider.dart';

class TopAppBar extends ConsumerWidget {
  const TopAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              // Profile avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: Image.network(
                  MockData.profileImageUrl,
                  width: 40,
                  height: 40,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Icon(Icons.person, color: AppColors.outline),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '食材管家',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999)),
            child: IconButton(
              icon: const Icon(Icons.search, color: AppColors.primary),
              onPressed: () {
                ref.read(searchActiveProvider.notifier).state = true;
              },
            ),
          ),
        ],
      ),
    );
  }
}
