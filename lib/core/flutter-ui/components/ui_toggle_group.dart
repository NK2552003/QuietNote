import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Chrome of the group container.
enum UiToggleGroupVariant {
  /// Inset track with a sliding selected pill (default).
  segmented,

  /// Standalone pills with no shared track.
  pill,

  /// Bordered, joined buttons.
  joined,

  /// Text-only with an underline on the selected item.
  underline,
}

class UiToggleOption<T> {
  const UiToggleOption({
    required this.value,
    required this.label,
    this.icon,
    this.intent,
    this.badge,
    this.tooltip,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;

  /// Overrides the selected-pill color (e.g. bullish for Buy, bearish for Sell).
  final UiIntent? intent;

  /// Small count/label chip rendered after the label.
  final String? badge;
  final String? tooltip;
  final bool enabled;
}

/// Segmented control (Buy / Sell, 1D / 1W / 1M) with single or multi select.
///
/// Single select uses [value] + [onChanged]; multi select uses [values] +
/// [onValuesChanged]. Both keep the same visual states.
class UiToggleGroup<T> extends StatelessWidget {
  const UiToggleGroup({
    super.key,
    required this.options,
    this.value,
    this.onChanged,
    this.values = const <Never>[],
    this.onValuesChanged,
    this.multiple = false,
    this.size = UiSize.sm,
    this.variant = UiToggleGroupVariant.segmented,
    this.density = UiDensity.comfortable,
    this.orientation = UiOrientation.horizontal,
    this.intent,
    this.expand = false,
    this.iconOnly = false,
    this.enabled = true,
    this.scrollableOnMobile = true,
    this.allowEmpty = true,
    this.label,
    this.semanticLabel,
  });

  final List<UiToggleOption<T>> options;

  /// Selected value (single-select mode).
  final T? value;
  final ValueChanged<T>? onChanged;

  /// Selected values (multi-select mode).
  final List<T> values;
  final ValueChanged<List<T>>? onValuesChanged;
  final bool multiple;

  final UiSize size;
  final UiToggleGroupVariant variant;
  final UiDensity density;
  final UiOrientation orientation;

  /// Group-level selected color; per-option [UiToggleOption.intent] wins.
  final UiIntent? intent;

  final bool expand;
  final bool iconOnly;
  final bool enabled;
  final bool scrollableOnMobile;

  /// When false, the last selected item cannot be deselected in multi mode.
  final bool allowEmpty;

  final String? label;
  final String? semanticLabel;

  bool _isSelected(UiToggleOption<T> o) =>
      multiple ? values.contains(o.value) : o.value == value;

  void _tap(UiToggleOption<T> o) {
    if (!multiple) {
      onChanged?.call(o.value);
      return;
    }
    final List<T> next = List<T>.from(values);
    if (next.contains(o.value)) {
      if (!allowEmpty && next.length == 1) return;
      next.remove(o.value);
    } else {
      next.add(o.value);
    }
    onValuesChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final BorderRadius radius = context.radius(size.radius(context));
    final bool vertical = orientation == UiOrientation.vertical;

    final List<Widget> items = <Widget>[
      for (int i = 0; i < options.length; i++)
        _UiToggleButton<T>(
          option: options[i],
          selected: _isSelected(options[i]),
          size: size,
          variant: variant,
          density: density,
          groupIntent: intent,
          iconOnly: iconOnly,
          first: i == 0,
          last: i == options.length - 1,
          onTap: enabled && options[i].enabled && (onChanged != null || onValuesChanged != null)
              ? () => _tap(options[i])
              : null,
        ),
    ];

    final Widget flow = vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: items,
          )
        : Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            children: <Widget>[
              for (final Widget item in items)
                expand ? Expanded(child: item) : item,
            ],
          );

    Widget container;
    switch (variant) {
      case UiToggleGroupVariant.segmented:
        container = Container(
          padding: EdgeInsets.all(context.sz(3)),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: radius,
            border: Border.all(color: c.border, width: theme.borders.hairline),
          ),
          child: flow,
        );
        break;
      case UiToggleGroupVariant.joined:
        container = Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: c.border, width: theme.borders.hairline),
          ),
          clipBehavior: Clip.antiAlias,
          child: flow,
        );
        break;
      case UiToggleGroupVariant.pill:
        container = Wrap(
          spacing: context.sp(theme.spacing.xs),
          runSpacing: context.sp(theme.spacing.xs),
          children: items,
        );
        break;
      case UiToggleGroupVariant.underline:
        container = DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: c.border,
                width: theme.borders.hairline,
              ),
            ),
          ),
          child: flow,
        );
        break;
    }

    if (label != null) {
      container = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label!,
            style: context.uiText.label.copyWith(color: c.foregroundMuted),
          ),
          SizedBox(height: context.sp(theme.spacing.xs)),
          container,
        ],
      );
    }

    final Widget result = Semantics(
      label: semanticLabel,
      enabled: enabled,
      child: Opacity(opacity: enabled ? 1 : 0.6, child: container),
    );

    if (!vertical &&
        !expand &&
        scrollableOnMobile &&
        variant != UiToggleGroupVariant.pill &&
        context.uiRes.isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: result,
      );
    }
    return result;
  }
}

class _UiToggleButton<T> extends StatelessWidget {
  const _UiToggleButton({
    required this.option,
    required this.selected,
    required this.size,
    required this.variant,
    required this.density,
    required this.iconOnly,
    required this.first,
    required this.last,
    required this.onTap,
    this.groupIntent,
  });

  final UiToggleOption<T> option;
  final bool selected;
  final UiSize size;
  final UiToggleGroupVariant variant;
  final UiDensity density;
  final bool iconOnly;
  final bool first;
  final bool last;
  final UiIntent? groupIntent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final double f = density.factor;
    final UiIntent? tint = option.intent ?? groupIntent;
    final bool enabled = onTap != null;

    final Color activeBg = switch (variant) {
      UiToggleGroupVariant.underline => const Color(0x00000000),
      _ => tint != null ? tint.color(context) : c.surface,
    };
    final Color activeFg = switch (variant) {
      UiToggleGroupVariant.underline => c.foreground,
      _ => tint != null ? tint.onColor(context) : c.foreground,
    };
    final BorderRadius radius = context.radius(
      variant == UiToggleGroupVariant.pill ? theme.radii.pill : theme.radii.md,
    );

    return UiInteractive(
      enabled: enabled,
      onTap: onTap,
      selected: selected,
      tooltip: option.tooltip ?? (iconOnly ? option.label : null),
      semanticLabel: option.label,
      borderRadius: radius,
      builder: (BuildContext ctx, UiInteractiveState s) => AnimatedContainer(
        duration: theme.motion.fast,
        curve: theme.motion.curve,
        constraints: BoxConstraints(minHeight: size.height(ctx) - ctx.sz(4)),
        padding: EdgeInsets.symmetric(
          horizontal: ctx.sp(iconOnly ? theme.spacing.sm : theme.spacing.md) * f,
          vertical: ctx.sp(theme.spacing.xs) * f,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: !enabled
              ? const Color(0x00000000)
              : selected
                  ? activeBg
                  : (s.hovered ? c.surfaceHover : const Color(0x00000000)),
          borderRadius:
              variant == UiToggleGroupVariant.underline ? null : radius,
          border: variant == UiToggleGroupVariant.pill
              ? Border.all(
                  color: selected ? activeBg : c.border,
                  width: theme.borders.hairline,
                )
              : variant == UiToggleGroupVariant.underline
                  ? Border(
                      bottom: BorderSide(
                        color: selected
                            ? (tint?.color(context) ?? c.primary)
                            : const Color(0x00000000),
                        width: theme.borders.focus,
                      ),
                    )
                  : null,
          boxShadow: selected && variant == UiToggleGroupVariant.segmented
              ? theme.shadows.sm
              : null,
        ),
        foregroundDecoration: s.focused ? uiFocusRing(ctx, radius) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (option.icon != null) ...<Widget>[
              Icon(
                option.icon,
                size: size.icon(ctx) * 0.95,
                color: !enabled
                    ? c.disabledForeground
                    : selected
                        ? activeFg
                        : c.foregroundMuted,
              ),
              if (!iconOnly) SizedBox(width: ctx.sp(theme.spacing.xs)),
            ],
            if (!iconOnly)
              Text(
                option.label,
                overflow: TextOverflow.ellipsis,
                style: size.textStyle(ctx).copyWith(
                      color: !enabled
                          ? c.disabledForeground
                          : selected
                              ? activeFg
                              : c.foregroundMuted,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            if (option.badge != null && !iconOnly) ...<Widget>[
              SizedBox(width: ctx.sp(theme.spacing.xs)),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: ctx.sp(theme.spacing.xs)),
                decoration: BoxDecoration(
                  color: selected
                      ? activeFg.withValues(alpha: 0.16)
                      : c.surfaceMuted,
                  borderRadius: ctx.radius(theme.radii.pill),
                ),
                child: Text(
                  option.badge!,
                  style: ctx.uiText.caption.copyWith(
                    color: selected ? activeFg : c.foregroundMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
