import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/recipe.dart';
import '../theme/app_theme.dart';
import 'shared/fk_card.dart';
import 'shared/fk_pill.dart';
import 'shared/recipe_cover_fallback.dart';
import 'shared/recipe_image.dart';

/// 卡片排布方式。
/// - [horizontal]:设计稿 `screens-3.jsx::RecipeCard`,左 120px 方形封面 + 右侧内容,
///   用于菜谱列表 / 我的食谱等多卡场景。
/// - [banner]:上图下文,顶部一张 16:9 大图完整展示菜品,用于首页「今日推荐」主推位。
enum RecipeCardLayout { horizontal, banner }

/// 横向卡:左封面图 + 右侧内容区(名称 / 时间·难度 / 食材匹配进度条 / 标签 pills)。
/// banner 模式则改为上图下文。
///
/// 进度条颜色根据匹配比例:满 = primary,≥0.7 = primaryLight,否则 warn(黄油黄)。
/// `useExpiring=true` 时在封面左上叠"临期"角标(黄油黄底)。
class RecipeCard extends StatelessWidget {
  final Recipe recipe;
  final int? matchedCount;
  final String? subtitle;
  final String? ingredientLabel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool useExpiring;
  final Object? heroTag;
  final RecipeCardLayout layout;

  const RecipeCard({
    super.key,
    required this.recipe,
    this.matchedCount,
    this.subtitle,
    this.ingredientLabel,
    this.trailing,
    this.onTap,
    this.useExpiring = false,
    this.heroTag,
    this.layout = RecipeCardLayout.horizontal,
  });

  @override
  Widget build(BuildContext context) {
    final total = recipe.ingredients.length;
    final matched = matchedCount ?? 0;

    if (layout == RecipeCardLayout.banner) {
      return Semantics(
        button: onTap != null,
        label: recipe.name,
        child: FkCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _BannerCover(
                recipe: recipe,
                useExpiring: useExpiring,
                heroTag: heroTag,
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _RecipeMeta(
                  recipe: recipe,
                  matched: matched,
                  total: total,
                  ingredientLabel: ingredientLabel,
                  expand: false,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      button: onTap != null,
      label: recipe.name,
      child: FkCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: SizedBox(
          height: 130,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Cover(
                recipe: recipe,
                useExpiring: useExpiring,
                heroTag: heroTag,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: _RecipeMeta(
                    recipe: recipe,
                    matched: matched,
                    total: total,
                    ingredientLabel: ingredientLabel,
                    expand: true,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// 卡片内容区,横向与 banner 两种布局共用。
/// `expand=true` 时撑满固定高度并把进度块顶到底部(横向卡);否则随内容收缩并在
/// 两块之间留固定间距(banner 卡)。
class _RecipeMeta extends StatelessWidget {
  final Recipe recipe;
  final int matched;
  final int total;
  final String? ingredientLabel;
  final bool expand;

  const _RecipeMeta({
    required this.recipe,
    required this.matched,
    required this.total,
    required this.ingredientLabel,
    required this.expand,
  });

  @override
  Widget build(BuildContext context) {
    final missing = (total - matched).clamp(0, total);
    final ratio = total == 0 ? 0.0 : matched / total;
    final progressColor = ratio >= 1.0
        ? AppColors.primary
        : ratio >= 0.7
        ? AppColors.primaryLight
        : AppColors.fkWarn;

    final nameBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          recipe.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        DefaultTextStyle.merge(
          style: GoogleFonts.manrope(
            fontSize: AppFontSize.xs,
            color: AppColors.onSurfaceVariant,
            height: 1.2,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 11,
                color: AppColors.onSurfaceVariant,
              ),
              const SizedBox(width: 3),
              Text('${recipe.cookingMinutes} 分钟'),
              const SizedBox(width: 10),
              Text('· ${recipe.difficultyLabel}'),
            ],
          ),
        ),
      ],
    );

    final progressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              ingredientLabel ?? '食材匹配 $matched/$total',
              style: GoogleFonts.manrope(
                fontSize: AppFontSize.xs,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
            const Spacer(),
            if (missing > 0)
              Text(
                '缺 $missing 件',
                style: GoogleFonts.manrope(
                  fontSize: AppFontSize.xs,
                  fontWeight: FontWeight.w600,
                  color: AppColors.fkDanger,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.surfaceContainer,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio.clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: progressColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        if (recipe.tags.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 22,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final tag in recipe.tags.take(2)) ...[
                  FkPill(label: tag, sm: true),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ],
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: expand
          ? MainAxisAlignment.spaceBetween
          : MainAxisAlignment.start,
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      children: [
        nameBlock,
        if (!expand) const SizedBox(height: AppSpacing.md),
        progressBlock,
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  final Recipe recipe;
  final bool useExpiring;
  final Object? heroTag;
  const _Cover({required this.recipe, required this.useExpiring, this.heroTag});

  @override
  Widget build(BuildContext context) {
    final cover = ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppRadius.xl),
        bottomLeft: Radius.circular(AppRadius.xl),
      ),
      child: _CoverImage(recipe: recipe, fallbackIconSize: 32),
    );
    final wrappedCover = heroTag == null
        ? cover
        : Hero(tag: heroTag!, child: cover);
    return SizedBox(
      width: 120,
      child: Stack(
        children: [
          wrappedCover,
          if (useExpiring)
            const Positioned(top: 8, left: 8, child: _ExpiringBadge()),
        ],
      ),
    );
  }
}

/// banner 封面:顶部 16:9 大图,内部复用 [_CoverImage](模糊铺底 + contain 完整图)。
class _BannerCover extends StatelessWidget {
  final Recipe recipe;
  final bool useExpiring;
  final Object? heroTag;
  const _BannerCover({
    required this.recipe,
    required this.useExpiring,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final cover = ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppRadius.xl),
        topRight: Radius.circular(AppRadius.xl),
      ),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: _CoverImage(recipe: recipe, fallbackIconSize: 44),
      ),
    );
    final wrappedCover = heroTag == null
        ? cover
        : Hero(tag: heroTag!, child: cover);
    if (!useExpiring) return wrappedCover;
    return Stack(
      children: [
        wrappedCover,
        const Positioned(top: 10, left: 10, child: _ExpiringBadge()),
      ],
    );
  }
}

/// 菜谱封面图,横向缩略图与 banner 共用。同一张图先模糊放大铺底填满整个盒子,再用
/// contain 把完整菜品叠在中间 —— 任意宽高比(横图/竖图)都完整展示、不裁切、不留生硬
/// 空白条。空图回落到按菜式分类着色的占位。
///
/// 列表场景下每行被 ListView 默认的 RepaintBoundary 缓存,模糊层只在该行重绘时计算一次,
/// 滚动平移不会逐帧重算。
class _CoverImage extends StatelessWidget {
  final Recipe recipe;
  final double fallbackIconSize;
  const _CoverImage({required this.recipe, required this.fallbackIconSize});

  @override
  Widget build(BuildContext context) {
    final source = recipe.imageUrl?.trim();
    final fallback = RecipeCoverFallback(
      category: recipe.category,
      iconSize: fallbackIconSize,
    );
    if (source == null || source.isEmpty) {
      return fallback;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // 软底:模糊铺底的边缘 / 加载失败时都不会露出黑边。
        const ColoredBox(color: AppColors.primarySoft),
        // 同图模糊放大铺满盒子。
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(
            sigmaX: 18,
            sigmaY: 18,
            tileMode: TileMode.clamp,
          ),
          child: RecipeImage(
            imageSource: source,
            fit: BoxFit.cover,
            fallback: const SizedBox.shrink(),
          ),
        ),
        // 轻微压暗,让清晰前景在杂乱铺底上更突出。
        const ColoredBox(color: Color(0x14000000)),
        // 完整菜品:contain 保证不裁切任何内容。
        RecipeImage(
          imageSource: source,
          fit: BoxFit.contain,
          semanticLabel: recipe.name,
          fallback: fallback,
        ),
      ],
    );
  }
}

class _ExpiringBadge extends StatelessWidget {
  const _ExpiringBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.fkWarn,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 10,
            color: Colors.white,
          ),
          const SizedBox(width: 2),
          Text(
            '临期',
            style: GoogleFonts.manrope(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
