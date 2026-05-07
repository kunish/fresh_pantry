import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

class AlertCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String name;
  final String subtitle;
  final String badge;
  final Color badgeBg;
  final Color badgeText;
  final String? storageTag;
  final VoidCallback? onConsume;
  final VoidCallback? onAddToCart;

  const AlertCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
    this.storageTag,
    this.onConsume,
    this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onConsume != null || onAddToCart != null,
      label: name,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: AppColors.onSurface.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                  ),
                  child: Icon(icon, color: iconColor, size: 26),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.manrope(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            subtitle,
                            style: GoogleFonts.manrope(
                              fontSize: 13,
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                          if (storageTag != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                storageTag!.toUpperCase(),
                                style: GoogleFonts.manrope(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _AlertActions(
              badge: badge,
              badgeBg: badgeBg,
              badgeText: badgeText,
              onConsume: onConsume,
              onAddToCart: onAddToCart,
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertActions extends StatelessWidget {
  final String badge;
  final Color badgeBg;
  final Color badgeText;
  final VoidCallback? onConsume;
  final VoidCallback? onAddToCart;

  const _AlertActions({
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
    required this.onConsume,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = [
      if (onConsume != null)
        _ActionButton(
          icon: Icons.check_circle_outline,
          label: '已消耗',
          color: AppColors.primary,
          onTap: onConsume!,
        ),
      if (onAddToCart != null)
        _ActionButton(
          icon: Icons.add_shopping_cart,
          label: '加入清单',
          color: AppColors.secondary,
          onTap: onAddToCart!,
        ),
    ];
    final badgeWidget = _StatusBadge(
      badge: badge,
      badgeBg: badgeBg,
      badgeText: badgeText,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...buttons, badgeWidget],
          );
        }

        return Row(
          children: [
            for (final (index, button) in buttons.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              button,
            ],
            const Spacer(),
            badgeWidget,
          ],
        );
      },
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String badge;
  final Color badgeBg;
  final Color badgeText;

  const _StatusBadge({
    required this.badge,
    required this.badgeBg,
    required this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      constraints: const BoxConstraints(minWidth: 70),
      decoration: BoxDecoration(
        color: badgeBg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        badge.toUpperCase(),
        textAlign: TextAlign.center,
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: badgeText,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 18),
              if (label != null) ...[
                const SizedBox(width: 6),
                Text(
                  label!,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
