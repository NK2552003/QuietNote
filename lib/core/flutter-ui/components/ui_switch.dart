import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// On/off switch with sizes, intents, inline icons, loading state and
/// label/description slots. Can also render as a full selectable row.
class UiSwitch extends StatelessWidget {
  const UiSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.label,
    this.description,
    this.enabled = true,
    this.loading = false,
    this.size = UiSize.md,
    this.intent = UiIntent.primary,
    this.density = UiDensity.comfortable,
    this.activeColor,
    this.onIcon,
    this.offIcon,
    this.leading,
    this.labelPosition = UiAlign.start,
    this.asCard = false,
    this.semanticLabel,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;
  final String? description;
  final bool enabled;

  /// Shows a spinner inside the knob while an async toggle settles.
  final bool loading;
  final UiSize size;
  final UiIntent intent;
  final UiDensity density;
  final Color? activeColor;

  /// Icons rendered inside the track for the on / off positions.
  final IconData? onIcon;
  final IconData? offIcon;

  /// Leading slot before the label (icon, avatar).
  final Widget? leading;

  /// `start` puts the label first (switch right-aligned), `end` reverses it.
  final UiAlign labelPosition;
  final bool asCard;
  final String? semanticLabel;

  double _scale(BuildContext context) {
    switch (size) {
      case UiSize.xs:
        return 0.72;
      case UiSize.sm:
        return 0.86;
      case UiSize.md:
        return 1;
      case UiSize.lg:
        return 1.15;
      case UiSize.xl:
        return 1.3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final double k = _scale(context);
    final double w = context.sz(theme.sizes.switchWidth) * k;
    final double h = context.sz(theme.sizes.switchHeight) * k;
    final double knob = h - context.sz(4) * k;
    final Color onColor = activeColor ?? intent.color(context);
    final bool interactive = enabled && !loading && onChanged != null;

    final Widget track = UiInteractive(
      enabled: interactive,
      onTap: interactive ? () => onChanged!(!value) : null,
      semanticLabel: semanticLabel ?? label,
      selected: value,
      builder: (BuildContext ctx, UiInteractiveState s) => AnimatedContainer(
        duration: theme.motion.fast,
        curve: theme.motion.curve,
        width: w,
        height: h,
        padding: EdgeInsets.all(ctx.sz(2) * k),
        decoration: BoxDecoration(
          color: !enabled
              ? c.disabledBackground
              : value
                  ? onColor
                  : (s.hovered ? c.borderStrong : c.border),
          borderRadius: ctx.radius(theme.radii.pill),
          boxShadow: value && s.hovered ? uiGlow(ctx, onColor) : null,
        ),
        foregroundDecoration:
            s.focused ? uiFocusRing(ctx, ctx.radius(theme.radii.pill)) : null,
        child: Stack(
          children: <Widget>[
            if (onIcon != null || offIcon != null)
              Positioned.fill(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Icon(
                      onIcon,
                      size: knob * 0.6,
                      color: intent.onColor(ctx).withValues(alpha: value ? 0.9 : 0),
                    ),
                    Icon(
                      offIcon,
                      size: knob * 0.6,
                      color: c.foregroundSubtle
                          .withValues(alpha: value ? 0 : 0.9),
                    ),
                  ],
                ),
              ),
            AnimatedAlign(
              duration: theme.motion.fast,
              curve: theme.motion.curve,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: knob,
                height: knob,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  boxShadow: theme.shadows.sm,
                ),
                child: loading
                    ? Padding(
                        padding: EdgeInsets.all(knob * 0.22),
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: onColor,
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );

    if (label == null && leading == null) return track;

    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null)
          Text(
            label!,
            style: context.uiText.body.copyWith(
              color: enabled ? c.foreground : c.disabledForeground,
            ),
          ),
        if (description != null) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xxs)),
          Text(
            description!,
            style: context.uiText.caption.copyWith(color: c.foregroundMuted),
          ),
        ],
      ],
    );

    final List<Widget> children = <Widget>[
      if (leading != null) ...<Widget>[
        leading!,
        SizedBox(width: context.sp(theme.spacing.md)),
      ],
      Expanded(child: text),
      SizedBox(width: context.sp(theme.spacing.md)),
      track,
    ];

    final Widget row = Row(
      children: labelPosition == UiAlign.end
          ? <Widget>[track, SizedBox(width: context.sp(theme.spacing.md)), Expanded(child: text)]
          : children,
    );

    if (!asCard) return row;
    return Container(
      padding: EdgeInsets.all(context.sp(theme.spacing.md) * density.factor),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: context.radius(theme.radii.lg),
        border: Border.all(color: c.border, width: theme.borders.hairline),
      ),
      child: row,
    );
  }
}
