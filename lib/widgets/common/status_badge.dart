import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';

class StatusBadge extends StatelessWidget {
  final FreshnessState state;
  final String? label;

  const StatusBadge({super.key, required this.state, this.label});

  @override
  Widget build(BuildContext context) {
    final (backgroundColor, textColor, defaultLabel) = switch (state) {
      FreshnessState.fresh => (
        AppColors.primaryFixed,
        AppColors.primary,
        '新鲜',
      ),
      FreshnessState.expiringSoon => (
        AppColors.secondaryContainer,
        AppColors.onSecondaryContainer,
        '即将过期',
      ),
      FreshnessState.expired => (
        AppColors.errorContainer,
        AppColors.error,
        '已过期',
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label ?? defaultLabel,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
