import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Per-instance style overrides. Every field defaults to a theme token when
/// null, so components never hardcode a value.
@immutable
class UiButtonStyle {
  const UiButtonStyle({
    this.background,
    this.foreground,
    this.borderColor,
    this.radius,
    this.gradient,
    this.shadow,
    this.textStyle,
    this.height,
    this.padding,
  });

  final Color? background;
  final Color? foreground;
  final Color? borderColor;
  final double? radius;
  final Gradient? gradient;
  final List<BoxShadow>? shadow;
  final TextStyle? textStyle;
  final double? height;
  final EdgeInsetsGeometry? padding;
}

/// Fully themed, responsive button.
///
/// Supports every variant/size/intent in the system plus loading, badge
/// counters, icon-only, split actions, full-width and link treatments.
/// Nothing is hardcoded — colors, spacing, motion and radii come from tokens.
class UiButton extends StatelessWidget {
  const UiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.onLongPress,
    this.variant = UiVariant.primary,
    this.size = UiSize.md,
    this.intent,
    this.density = UiDensity.comfortable,
    this.leadingIcon,
    this.trailingIcon,
    this.leading,
    this.trailing,
    this.loading = false,
    this.loadingLabel,
    this.expand = false,
    this.expandOnMobile = false,
    this.tooltip,
    this.badgeCount,
    this.selected = false,
    this.iconOnly = false,
    this.rounded = false,
    this.elevate,
    this.style,
    this.semanticLabel,
    this.autofocus = false,
    this.focusNode,
    this.splitAction,
    this.splitIcon = Icons.expand_more,
    this.hideLabelOnMobile = false,
  });

  /// Icon-only shorthand that keeps an accessible label.
  const UiButton.icon({
    Key? key,
    required IconData icon,
    required String label,
    VoidCallback? onPressed,
    UiVariant variant = UiVariant.ghost,
    UiSize size = UiSize.md,
    UiIntent? intent,
    bool loading = false,
    bool selected = false,
    bool rounded = true,
    String? tooltip,
    UiButtonStyle? style,
  }) : this(
          key: key,
          label: label,
          onPressed: onPressed,
          variant: variant,
          size: size,
          intent: intent,
          leadingIcon: icon,
          loading: loading,
          selected: selected,
          rounded: rounded,
          iconOnly: true,
          expandOnMobile: false,
          tooltip: tooltip ?? label,
          style: style,
        );

  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final UiVariant variant;
  final UiSize size;

  /// Tints `soft`, `outline`, `ghost` and `link` variants; ignored by the
  /// solid variants that already carry their own semantic color.
  final UiIntent? intent;
  final UiDensity density;
  final IconData? leadingIcon;
  final IconData? trailingIcon;

  /// Arbitrary leading/trailing slots (avatar, spinner, badge...).
  final Widget? leading;
  final Widget? trailing;
  final bool loading;
  final String? loadingLabel;
  final bool expand;

  /// Buttons stretch full-width on phones by default (mobile-first pattern).
  final bool expandOnMobile;
  final String? tooltip;

  /// Optional counter chip rendered after the label.
  final int? badgeCount;
  final bool selected;
  final bool iconOnly;
  final bool rounded;
  final bool? elevate;
  final UiButtonStyle? style;
  final String? semanticLabel;
  final bool autofocus;
  final FocusNode? focusNode;

  /// When set, renders a split button: the main area triggers [onPressed] and
  /// the attached caret triggers [splitAction].
  final VoidCallback? splitAction;
  final IconData splitIcon;

  /// Collapses to icon-only on phones to save horizontal space.
  final bool hideLabelOnMobile;

  bool get _enabled => (onPressed != null || onLongPress != null) && !loading;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool compactLabel =
        iconOnly || (hideLabelOnMobile && context.uiRes.isMobile);
    final BorderRadius radius = context.radius(
      style?.radius ?? (rounded ? theme.radii.pill : size.radius(context)),
    );
    final bool fullWidth = !compactLabel &&
        (expand || (expandOnMobile && context.uiRes.isMobile));

    Widget core = UiInteractive(
      enabled: _enabled,
      onTap: onPressed,
      onLongPress: onLongPress,
      selected: selected,
      autofocus: autofocus,
      focusNode: focusNode,
      semanticLabel: semanticLabel ?? label,
      builder: (BuildContext ctx, UiInteractiveState s) {
        final _ButtonStyle st = _resolve(ctx, s);
        final double h = style?.height ?? size.height(ctx);
        return AnimatedContainer(
          duration: theme.motion.fast,
          curve: theme.motion.curve,
          height: h,
          width: compactLabel ? h : null,
          padding: compactLabel
              ? EdgeInsets.zero
              : (style?.padding ?? size.padding(ctx, density: density)),
          constraints: compactLabel
              ? null
              : BoxConstraints(minWidth: ctx.sz(theme.sizes.minTapTarget)),
          decoration: BoxDecoration(
            color: st.gradient == null ? st.background : null,
            gradient: st.gradient,
            borderRadius: radius,
            border: st.borderColor == null
                ? null
                : Border.all(
                    color: st.borderColor!,
                    width: s.focused || selected
                        ? theme.borders.thick
                        : theme.borders.hairline,
                  ),
            boxShadow: style?.shadow ??
                (st.elevated && (s.hovered || selected)
                    ? theme.shadows.md
                    : (st.elevated ? theme.shadows.sm : null)),
          ),
          foregroundDecoration: s.focused ? uiFocusRing(ctx, radius) : null,
          child: _content(ctx, st, compactLabel, fullWidth),
        );
      },
    );

    if (splitAction != null && !compactLabel) {
      core = _wrapSplit(context, core, radius);
    }
    if (fullWidth) core = SizedBox(width: double.infinity, child: core);
    if (tooltip != null) core = Tooltip(message: tooltip!, child: core);
    return core;
  }

  Widget _wrapSplit(BuildContext context, Widget main, BorderRadius radius) {
    final theme = context.ui;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        main,
        SizedBox(width: context.sp(theme.spacing.xxs)),
        UiButton.icon(
          icon: splitIcon,
          label: '$label options',
          variant: variant,
          size: size,
          intent: intent,
          onPressed: splitAction,
          style: style,
        ),
      ],
    );
  }

  Widget _content(
    BuildContext ctx,
    _ButtonStyle st,
    bool compactLabel,
    bool fullWidth,
  ) {
    final theme = ctx.ui;
    final double gap = size.gap(ctx, density: density);
    final TextStyle text = (style?.textStyle ?? size.textStyle(ctx)).copyWith(
      color: st.foreground,
      decoration: variant == UiVariant.link ? TextDecoration.underline : null,
      decorationColor: st.foreground,
    );

    final Widget? spinner = loading
        ? SizedBox(
            width: size.icon(ctx),
            height: size.icon(ctx),
            child: CircularProgressIndicator(
              strokeWidth: theme.borders.thick,
              valueColor: AlwaysStoppedAnimation<Color>(st.foreground),
            ),
          )
        : null;

    final Widget? lead = spinner ??
        leading ??
        (leadingIcon == null
            ? null
            : Icon(leadingIcon, size: size.icon(ctx), color: st.foreground));

    if (compactLabel) {
      return Center(
        child: lead ??
            Text(
              label.isEmpty ? '' : label.substring(0, 1).toUpperCase(),
              style: text,
            ),
      );
    }

    return Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (lead != null) ...<Widget>[lead, SizedBox(width: gap)],
        Flexible(
          child: Text(
            loading ? (loadingLabel ?? label) : label,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: text,
          ),
        ),
        if (badgeCount != null) ...<Widget>[
          SizedBox(width: gap),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ctx.sp(theme.spacing.xs),
              vertical: ctx.sp(theme.spacing.none),
            ),
            decoration: BoxDecoration(
              color: st.foreground.withValues(alpha: 0.16),
              borderRadius: ctx.radius(theme.radii.pill),
            ),
            child: Text(
              '$badgeCount',
              style: ctx.uiText.caption.copyWith(
                color: st.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        if (trailing != null) ...<Widget>[SizedBox(width: gap), trailing!],
        if (trailingIcon != null) ...<Widget>[
          SizedBox(width: gap),
          Icon(trailingIcon, size: size.icon(ctx), color: st.foreground),
        ],
      ],
    );
  }

  _ButtonStyle _resolve(BuildContext context, UiInteractiveState s) {
    final c = context.uiColors;
    final Color tint = (intent ?? UiIntent.primary).color(context);
    Color hoverMix(Color base, Color hover) => s.active ? hover : base;

    if (style?.background != null || style?.foreground != null) {
      return _ButtonStyle(
        background: style?.background ?? Colors.transparent,
        foreground: style?.foreground ?? c.foreground,
        borderColor: style?.borderColor,
        gradient: style?.gradient,
      );
    }

    if (!s.enabled) {
      final bool transparent = variant == UiVariant.ghost ||
          variant == UiVariant.link ||
          variant == UiVariant.outline;
      return _ButtonStyle(
        background: transparent ? Colors.transparent : c.disabledBackground,
        foreground: c.disabledForeground,
        borderColor: variant == UiVariant.outline ? c.border : null,
      );
    }

    final bool on = selected;
    switch (variant) {
      case UiVariant.primary:
        return _ButtonStyle(
          background: hoverMix(c.primary, c.primaryHover),
          foreground: c.onPrimary,
          elevated: elevate ?? true,
        );
      case UiVariant.secondary:
        return _ButtonStyle(
          background: hoverMix(on ? c.surfaceHover : c.secondary, c.surfaceHover),
          foreground: c.onSecondary,
          borderColor: c.border,
          elevated: elevate ?? false,
        );
      case UiVariant.ghost:
        return _ButtonStyle(
          background: s.active || on ? c.surfaceHover : Colors.transparent,
          foreground: intent == null ? c.foreground : tint,
        );
      case UiVariant.outline:
        return _ButtonStyle(
          background: s.active || on ? c.surfaceHover : Colors.transparent,
          foreground: intent == null ? c.foreground : tint,
          borderColor: intent == null ? c.borderStrong : tint.withValues(alpha: 0.5),
        );
      case UiVariant.soft:
        return _ButtonStyle(
          background: tint.withValues(alpha: s.active || on ? 0.22 : 0.12),
          foreground: tint,
          borderColor: tint.withValues(alpha: 0.24),
        );
      case UiVariant.link:
        return _ButtonStyle(
          background: Colors.transparent,
          foreground: intent == null ? c.foreground : tint,
        );
      case UiVariant.destructive:
        return _ButtonStyle(
          background:
              hoverMix(c.destructive, c.destructive.withValues(alpha: 0.85)),
          foreground: c.onDestructive,
          elevated: elevate ?? true,
        );
      case UiVariant.success:
        return _ButtonStyle(
          background: hoverMix(c.bullish, c.bullish.withValues(alpha: 0.85)),
          foreground: c.onPrimary,
          elevated: elevate ?? true,
        );
    }
  }
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.background,
    required this.foreground,
    this.borderColor,
    this.elevated = false,
    this.gradient,
  });

  final Color background;
  final Color foreground;
  final Color? borderColor;
  final bool elevated;
  final Gradient? gradient;
}
