import 'package:flutter/material.dart';
import '../../models/storage_area.dart';
import '../../theme/app_theme.dart';
import '../../utils/storage_labels.dart';

class StorageSummaryCard extends StatelessWidget {
  final StorageArea area;

  const StorageSummaryCard({super.key, required this.area});

  IconData get _icon => storageIconFor(area.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.xxl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(_icon, color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    area.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                '${area.itemCount} 件',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: LinearProgressIndicator(
              value: area.capacityPercent,
              minHeight: 8,
              backgroundColor: AppColors.surfaceContainerHighest,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(area.capacityPercent * 100).toInt()}% 容量',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
