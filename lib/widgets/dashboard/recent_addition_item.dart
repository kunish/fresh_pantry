import 'package:flutter/material.dart';
import '../../models/ingredient.dart';
import '../../theme/app_theme.dart';
import '../shared/category_icon.dart';

class RecentAdditionItem extends StatelessWidget {
  final Ingredient item;

  const RecentAdditionItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            CategoryIconAvatar(category: item.category, size: 64, iconSize: 30),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    _addedAtLabel(item.addedAt),
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${item.quantity} ${item.unit}'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 96,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: LinearProgressIndicator(
                      value: item.freshnessPercent,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceContainerHigh,
                      valueColor: const AlwaysStoppedAnimation(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _addedAtLabel(DateTime? addedAt) {
    if (addedAt == null) return '最近添加';

    var elapsed = DateTime.now().difference(addedAt);
    if (elapsed.isNegative) elapsed = Duration.zero;

    if (elapsed.inMinutes < 1) return '刚刚添加';
    if (elapsed.inHours < 1) return '${elapsed.inMinutes}分钟前添加';
    if (elapsed.inHours < 24) return '${elapsed.inHours}小时前添加';
    if (elapsed.inHours < 48) return '昨天添加';
    return '${elapsed.inDays}天前添加';
  }
}
