import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Checkbox with tri-state support, sizes, intents, card mode and
/// label/description slots.
class UiCheckbox extends StatelessWidget {
  const UiCheckbox({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.labelWidget,
    this.description,
    this.indeterminate = false,
    this.enabled = true,
    this.size = UiSize.md,
    this.intent = UiIntent.primary,
    this.density = UiDensity.comfortable,
    this.error = false,
    this.errorText,
    this.trailing,
    this.asCard = false,
    this.reverse = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final Widget? labelWidget;
  final String? description;
  final bool indeterminate;
  final bool enabled;
  final UiSize size;
  final UiIntent intent;
  final UiDensity density;
  final bool error;
  final String? errorText;

  /// Trailing slot (badge, price, count).
  final Widget? trailing;

  /// Renders the row inside a selectable surface (settings / filter lists).
  final bool asCard;

  /// Places the box after the label (right-aligned lists).
  final bool reverse;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final double f = density.factor;
    final double dim = size.icon(context) *
        (context.sz(theme.sizes.checkbox) / context.sz(theme.sizes.iconMd));
    final bool active = value || indeterminate;
    final Color accent = error ? c.destructive : intent.color(context);

    return UiInteractive(
      enabled: enabled && onChanged != null,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: semanticLabel ?? label,
      selected: value,
      builder: (BuildContext ctx, UiInteractiveState s) {
        final Widget box = AnimatedContainer(
          duration: theme.motion.fast,
          curve: theme.motion.curve,
          width: dim,
          height: dim,
          margin: EdgeInsets.only(top: ctx.sp(theme.spacing.xxs)),
          decoration: BoxDecoration(
            color: !enabled
                ? c.disabledBackground
                : active
                    ? accent
                    : c.surface,
            borderRadius: ctx.radius(theme.radii.sm),
            border: Border.all(
              color: !enabled
                  ? c.border
                  : active
                      ? accent
                      : error
                          ? c.destructive
                          : (s.hovered ? c.borderStrong : c.border),
              width: theme.borders.thick,
            ),
            boxShadow: active && s.hovered ? uiGlow(ctx, accent) : null,
          ),
          foregroundDecoration:
              s.focused ? uiFocusRing(ctx, ctx.radius(theme.radii.sm)) : null,
          child: AnimatedSwitcher(
            duration: theme.motion.fast,
            child: active
                ? Icon(
                    indeterminate ? Icons.remove : Icons.check,
                    key: ValueKey<bool>(indeterminate),
                    size: dim * 0.8,
                    color: enabled
                        ? intent.onColor(ctx)
                        : c.disabledForeground,
                  )
                : const SizedBox.shrink(),
          ),
        );

        final Widget text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (labelWidget != null)
              labelWidget!
            else if (label != null)
              Text(
                label!,
                style: ctx.uiText.body.copyWith(
                  color: enabled ? c.foreground : c.disabledForeground,
                  fontWeight: value ? FontWeight.w600 : null,
                ),
              ),
            if (description != null) ...<Widget>[
              SizedBox(height: ctx.sp(theme.spacing.xxs)),
              Text(
                description!,
                style: ctx.uiText.caption.copyWith(color: c.foregroundMuted),
              ),
            ],
            if (errorText != null) ...<Widget>[
              SizedBox(height: ctx.sp(theme.spacing.xxs)),
              Text(
                errorText!,
                style: ctx.uiText.caption.copyWith(color: c.destructive),
              ),
            ],
          ],
        );

        final bool hasText = label != null || labelWidget != null || description != null;
        final List<Widget> row = <Widget>[
          box,
          if (hasText) ...<Widget>[
            SizedBox(width: ctx.sp(theme.spacing.sm) * f),
            Expanded(child: text),
          ],
          if (trailing != null) ...<Widget>[
            SizedBox(width: ctx.sp(theme.spacing.sm)),
            trailing!,
          ],
        ];

        final Widget content = Row(
          mainAxisSize: hasText ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reverse ? row.reversed.toList() : row,
        );

        if (!asCard) return content;
        return AnimatedContainer(
          duration: theme.motion.fast,
          padding: EdgeInsets.all(ctx.sp(theme.spacing.md) * f),
          decoration: BoxDecoration(
            color: value
                ? Color.alphaBlend(accent.withValues(alpha: 0.08), c.surface)
                : (s.hovered ? c.surfaceHover : c.surface),
            borderRadius: ctx.radius(theme.radii.lg),
            border: Border.all(
              color: value ? accent : c.border,
              width: value ? theme.borders.thick : theme.borders.hairline,
            ),
          ),
          child: content,
        );
      },
    );
  }
}
