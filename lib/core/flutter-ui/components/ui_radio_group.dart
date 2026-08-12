import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_field.dart';

/// Radio group with sizes, intents, orientation, descriptions and validation.
class UiRadioGroup<T> extends StatelessWidget {
  const UiRadioGroup({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
    this.label,
    this.helperText,
    this.errorText,
    this.size = UiSize.md,
    this.intent = UiIntent.primary,
    this.density = UiDensity.comfortable,
    this.orientation = UiOrientation.vertical,
    this.horizontalFromTablet = false,
    this.enabled = true,
    this.required = false,
    this.reverse = false,
    this.dividers = false,
    this.optionBuilder,
    this.semanticLabel,
  });

  final List<UiOption<T>> options;
  final T? value;
  final ValueChanged<T>? onChanged;

  final String? label;
  final String? helperText;
  final String? errorText;

  final UiSize size;
  final UiIntent intent;
  final UiDensity density;
  final UiOrientation orientation;

  /// Lays the tiles out in a row from tablet width up.
  final bool horizontalFromTablet;

  final bool enabled;
  final bool required;

  /// Places the radio dot after the label (settings lists).
  final bool reverse;

  /// Hairline separators between tiles (vertical orientation only).
  final bool dividers;

  /// Replaces the default tile rendering.
  final Widget Function(BuildContext context, UiOption<T> option, bool selected)?
      optionBuilder;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool horizontal = orientation == UiOrientation.horizontal ||
        (horizontalFromTablet && !context.uiRes.isMobile);
    final bool invalid = errorText != null;
    final double gap = context.sp(theme.spacing.md) * density.factor;

    final List<Widget> tiles = <Widget>[
      for (final UiOption<T> o in options)
        optionBuilder != null
            ? optionBuilder!(context, o, o.value == value)
            : _UiRadioTile<T>(
                option: o,
                selected: o.value == value,
                size: size,
                intent: invalid ? UiIntent.danger : intent,
                density: density,
                reverse: reverse,
                enabled: enabled && o.enabled && onChanged != null,
                onTap: () => onChanged?.call(o.value),
              ),
    ];

    final Widget body = horizontal
        ? Wrap(spacing: gap, runSpacing: gap, children: tiles)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < tiles.length; i++) ...<Widget>[
                if (i > 0) ...<Widget>[
                  if (dividers)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: gap / 2),
                      child: Container(
                        height: theme.borders.hairline,
                        color: theme.colors.border,
                      ),
                    )
                  else
                    SizedBox(height: gap),
                ],
                tiles[i],
              ],
            ],
          );

    final Widget group = Semantics(
      label: semanticLabel ?? label,
      enabled: enabled,
      child: body,
    );

    if (label == null && helperText == null && errorText == null) return group;
    return UiField(
      label: label,
      helper: helperText,
      error: errorText,
      required: required,
      density: density,
      enabled: enabled,
      child: group,
    );
  }
}

class _UiRadioTile<T> extends StatelessWidget {
  const _UiRadioTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
    required this.size,
    required this.intent,
    required this.density,
    required this.reverse,
  });

  final UiOption<T> option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  final UiSize size;
  final UiIntent intent;
  final UiDensity density;
  final bool reverse;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final Color accent = intent.color(context);
    final double dim = context.sz(theme.sizes.radio) *
        (size == UiSize.lg || size == UiSize.xl ? 1.25 : size == UiSize.xs ? 0.8 : 1);

    return UiInteractive(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      selected: selected,
      semanticLabel: option.label,
      builder: (BuildContext ctx, UiInteractiveState s) {
        final Widget dot = AnimatedContainer(
          duration: theme.motion.fast,
          curve: theme.motion.curve,
          width: dim,
          height: dim,
          margin: EdgeInsets.only(top: ctx.sp(theme.spacing.xxs)),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: enabled ? c.surface : c.disabledBackground,
            border: Border.all(
              color: !enabled
                  ? c.border
                  : selected
                      ? accent
                      : (s.hovered ? c.borderStrong : c.border),
              width: theme.borders.thick,
            ),
            boxShadow: selected && s.hovered ? uiGlow(ctx, accent) : null,
          ),
          foregroundDecoration: s.focused
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: c.focusRing,
                    width: theme.borders.focus,
                  ),
                )
              : null,
          alignment: Alignment.center,
          child: AnimatedScale(
            duration: theme.motion.fast,
            curve: theme.motion.curve,
            scale: selected ? 1 : 0,
            child: Container(
              width: dim * 0.5,
              height: dim * 0.5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled ? accent : c.disabledForeground,
              ),
            ),
          ),
        );

        final Widget text = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (option.icon != null) ...<Widget>[
                  Icon(
                    option.icon,
                    size: size.icon(ctx),
                    color: selected ? accent : c.foregroundMuted,
                  ),
                  SizedBox(width: ctx.sp(theme.spacing.xs)),
                ],
                Flexible(
                  child: Text(
                    option.label,
                    style: size.textStyle(ctx).copyWith(
                          color: enabled ? c.foreground : c.disabledForeground,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ),
                  ),
                ),
              ],
            ),
            if (option.description != null) ...<Widget>[
              SizedBox(height: ctx.sp(theme.spacing.xxs)),
              Text(
                option.description!,
                style: ctx.uiText.caption.copyWith(color: c.foregroundMuted),
              ),
            ],
          ],
        );

        final List<Widget> row = <Widget>[
          dot,
          SizedBox(width: ctx.sp(theme.spacing.sm) * density.factor),
          Flexible(child: text),
          if (option.trailingLabel != null) ...<Widget>[
            SizedBox(width: ctx.sp(theme.spacing.sm)),
            Text(
              option.trailingLabel!,
              style: ctx.uiText.caption.copyWith(color: c.foregroundSubtle),
            ),
          ],
        ];

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: reverse ? row.reversed.toList() : row,
        );
      },
    );
  }
}
