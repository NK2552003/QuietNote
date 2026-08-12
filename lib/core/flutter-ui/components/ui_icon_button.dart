import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Square icon-only button.
class UiIconButton extends StatelessWidget {
  const UiIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.variant = UiVariant.ghost,
    this.size = UiSize.md,
    this.tooltip,
    this.badgeCount,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final UiVariant variant;
  final UiSize size;
  final String? tooltip;
  final int? badgeCount;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final BorderRadius radius = context.radius(theme.radii.lg);
    final double dim = size.height(context);

    Widget child = UiInteractive(
      enabled: onPressed != null,
      onTap: onPressed,
      semanticLabel: tooltip ?? 'button',
      builder: (BuildContext ctx, UiInteractiveState s) {
        final c = ctx.uiColors;
        final Color bg = !s.enabled
            ? (variant == UiVariant.ghost
                ? Colors.transparent
                : c.disabledBackground)
            : switch (variant) {
                UiVariant.primary => s.hovered ? c.primaryHover : c.primary,
                UiVariant.destructive => c.destructive,
                UiVariant.success => c.bullish,
                UiVariant.secondary =>
                  s.hovered ? c.surfaceHover : c.secondary,
                _ => s.hovered ? c.surfaceHover : Colors.transparent,
              };
        final Color fg = !s.enabled
            ? c.disabledForeground
            : (variant == UiVariant.primary ||
                    variant == UiVariant.destructive ||
                    variant == UiVariant.success)
                ? c.onPrimary
                : c.foreground;
        return AnimatedContainer(
          duration: theme.motion.fast,
          width: dim,
          height: dim,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: radius,
            border: variant == UiVariant.outline
                ? Border.all(color: c.borderStrong, width: theme.borders.hairline)
                : null,
          ),
          foregroundDecoration: s.focused ? uiFocusRing(ctx, radius) : null,
          child: Icon(icon, size: size.icon(ctx), color: fg),
        );
      },
    );

    if (badgeCount != null && badgeCount! > 0) {
      child = Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          child,
          Positioned(
            right: -context.sp(theme.spacing.xxs),
            top: -context.sp(theme.spacing.xxs),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.sp(theme.spacing.xs),
                vertical: context.sp(theme.spacing.none),
              ),
              constraints: BoxConstraints(minWidth: context.sz(16)),
              decoration: BoxDecoration(
                color: theme.colors.destructive,
                borderRadius: context.radius(theme.radii.pill),
              ),
              alignment: Alignment.center,
              child: Text(
                badgeCount! > 99 ? '99+' : '$badgeCount',
                style: context.uiText.caption
                    .copyWith(color: theme.colors.onDestructive),
              ),
            ),
          ),
        ],
      );
    }
    if (tooltip != null) child = Tooltip(message: tooltip!, child: child);
    return child;
  }
}
