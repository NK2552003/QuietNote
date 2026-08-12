import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Single-value slider (position size, leverage, price alert bands).
///
/// Adds: sizes, intents, tick marks, min/max captions, value bubble,
/// preset stops, prefix/suffix formatting and disabled/read-only states.
class UiSlider extends StatelessWidget {
  const UiSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeEnd,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.label,
    this.helper,
    this.valueFormatter,
    this.enabled = true,
    this.intent = UiIntent.primary,
    this.size = UiSize.md,
    this.showValue = true,
    this.showBounds = false,
    this.showTicks = false,
    this.presets = const <double>[],
    this.presetFormatter,
    this.leading,
    this.trailing,
    this.semanticLabel,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final String? helper;
  final UiValueFormatter? valueFormatter;
  final bool enabled;
  final UiIntent intent;
  final UiSize size;

  /// Shows the formatted current value beside the label.
  final bool showValue;

  /// Shows min / max captions under the track.
  final bool showBounds;

  /// Renders tick marks when [divisions] is set.
  final bool showTicks;

  /// Quick-jump values rendered as chips under the track (e.g. 25/50/75/100%).
  final List<double> presets;
  final UiValueFormatter? presetFormatter;

  /// Slots on either side of the track (icons, steppers).
  final Widget? leading;
  final Widget? trailing;
  final String? semanticLabel;

  double _thumb(BuildContext context) {
    switch (size) {
      case UiSize.xs:
        return context.sz(7);
      case UiSize.sm:
        return context.sz(8.5);
      case UiSize.md:
        return context.sz(10);
      case UiSize.lg:
        return context.sz(12);
      case UiSize.xl:
        return context.sz(14);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color active = intent.color(context);
    final UiValueFormatter fmt = valueFormatter ?? uiCompactNumber;
    final double v = value.clamp(min, max);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null || showValue)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label ?? '',
                  style: context.uiText.label
                      .copyWith(color: theme.colors.foregroundMuted),
                ),
              ),
              if (showValue)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.sp(theme.spacing.sm),
                    vertical: context.sp(theme.spacing.xxs),
                  ),
                  decoration: BoxDecoration(
                    color: active.withValues(alpha: 0.12),
                    borderRadius: context.radius(theme.radii.pill),
                  ),
                  child: Text(
                    fmt(v),
                    style: context.uiText.numeric.copyWith(
                      color: enabled ? active : theme.colors.disabledForeground,
                    ),
                  ),
                ),
            ],
          ),
        Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              SizedBox(width: context.sp(theme.spacing.xs)),
            ],
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: context.sz(theme.sizes.trackThickness) * 0.6,
                  activeTrackColor:
                      enabled ? active : theme.colors.disabledForeground,
                  inactiveTrackColor: theme.colors.surfaceMuted,
                  thumbColor: theme.colors.surface,
                  overlayColor: active.withValues(alpha: 0.12),
                  valueIndicatorColor: active,
                  valueIndicatorTextStyle: context.uiText.caption
                      .copyWith(color: intent.onColor(context)),
                  showValueIndicator: ShowValueIndicator.onDrag,
                  activeTickMarkColor: showTicks
                      ? intent.onColor(context).withValues(alpha: 0.7)
                      : Colors.transparent,
                  inactiveTickMarkColor: showTicks
                      ? theme.colors.borderStrong
                      : Colors.transparent,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _thumb(context),
                    elevation: 2,
                  ),
                  trackShape: const RoundedRectSliderTrackShape(),
                ),
                child: Slider(
                  value: v,
                  min: min,
                  max: max,
                  divisions: divisions,
                  label: fmt(v),
                  semanticFormatterCallback: (double d) =>
                      '${semanticLabel ?? label ?? 'Value'} ${fmt(d)}',
                  onChanged: enabled ? onChanged : null,
                  onChangeEnd: enabled ? onChangeEnd : null,
                ),
              ),
            ),
            if (trailing != null) ...<Widget>[
              SizedBox(width: context.sp(theme.spacing.xs)),
              trailing!,
            ],
          ],
        ),
        if (showBounds)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                fmt(min),
                style: context.uiText.caption
                    .copyWith(color: theme.colors.foregroundSubtle),
              ),
              Text(
                fmt(max),
                style: context.uiText.caption
                    .copyWith(color: theme.colors.foregroundSubtle),
              ),
            ],
          ),
        if (presets.isNotEmpty) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xs)),
          Wrap(
            spacing: context.sp(theme.spacing.xs),
            runSpacing: context.sp(theme.spacing.xs),
            children: <Widget>[
              for (final double p in presets)
                UiInteractive(
                  enabled: enabled && onChanged != null,
                  onTap: () {
                    onChanged?.call(p);
                    onChangeEnd?.call(p);
                  },
                  semanticLabel: (presetFormatter ?? fmt)(p),
                  builder: (BuildContext ctx, UiInteractiveState s) =>
                      AnimatedContainer(
                    duration: theme.motion.fast,
                    padding: EdgeInsets.symmetric(
                      horizontal: ctx.sp(theme.spacing.sm),
                      vertical: ctx.sp(theme.spacing.xxs),
                    ),
                    decoration: BoxDecoration(
                      color: v == p
                          ? active.withValues(alpha: 0.16)
                          : (s.hovered
                              ? theme.colors.surfaceHover
                              : Colors.transparent),
                      borderRadius: ctx.radius(theme.radii.pill),
                      border: Border.all(
                        color: v == p ? active : theme.colors.border,
                        width: theme.borders.hairline,
                      ),
                    ),
                    child: Text(
                      (presetFormatter ?? fmt)(p),
                      style: ctx.uiText.caption.copyWith(
                        color: v == p ? active : theme.colors.foregroundMuted,
                        fontWeight: v == p ? FontWeight.w600 : null,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
        if (helper != null) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.xxs)),
          Text(
            helper!,
            style: context.uiText.caption
                .copyWith(color: theme.colors.foregroundMuted),
          ),
        ],
      ],
    );
  }
}
