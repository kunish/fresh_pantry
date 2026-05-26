import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class AiDraftReviewBanner extends StatelessWidget {
  const AiDraftReviewBanner({
    super.key,
    required this.sourceUrl,
    required this.onRegenerate,
    required this.onDiscard,
    this.isLoading = false,
  });

  final String? sourceUrl;
  final VoidCallback onRegenerate;
  final VoidCallback onDiscard;
  final bool isLoading;

  static const _actionButtonHeight = 44.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('ai_draft_review_banner'),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.primaryFixed.withValues(alpha: 0.35),
        border: Border.all(color: AppColors.primaryFixed),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ AI 草稿已填入，请核对下方字段',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          if (sourceUrl != null && sourceUrl!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '来源: $sourceUrl',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: _actionButtonHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('ai_draft_review_regenerate'),
                    style: _outlinedStyle(context),
                    onPressed: isLoading ? null : onRegenerate,
                    child: const Text('重新生成'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    key: const Key('ai_draft_review_discard'),
                    style: _outlinedStyle(context),
                    onPressed: isLoading ? null : onDiscard,
                    child: const Text('丢弃草稿'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ButtonStyle _outlinedStyle(BuildContext context) {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(0, _actionButtonHeight),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      textStyle: Theme.of(context).textTheme.labelLarge,
    );
  }
}
