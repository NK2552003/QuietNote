import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ui_theme.dart';

/// A selectable option used by selects, radios, toggles, menus and filters.
///
/// Nothing here is visual — components decide how to render an option.
class UiOption<T> {
  const UiOption({
    required this.value,
    required this.label,
    this.description,
    this.icon,
    this.trailingLabel,
    this.badge,
    this.group,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? description;
  final IconData? icon;

  /// Optional right-aligned hint (shortcut, price, count...).
  final String? trailingLabel;

  /// Optional short badge text rendered next to the label.
  final String? badge;

  /// Optional group header this option belongs to.
  final String? group;
  final bool enabled;

  UiOption<T> copyWith({
    T? value,
    String? label,
    String? description,
    IconData? icon,
    String? trailingLabel,
    String? badge,
    String? group,
    bool? enabled,
  }) =>
      UiOption<T>(
        value: value ?? this.value,
        label: label ?? this.label,
        description: description ?? this.description,
        icon: icon ?? this.icon,
        trailingLabel: trailingLabel ?? this.trailingLabel,
        badge: badge ?? this.badge,
        group: group ?? this.group,
        enabled: enabled ?? this.enabled,
      );
}

/// Shared enums + helpers used across components. Nothing visual is hardcoded;
/// every mapping resolves against [UiTheme].
enum UiSize { xs, sm, md, lg, xl }

/// Visual treatments available to actionable / container components.
enum UiVariant {
  primary,
  secondary,
  ghost,
  outline,
  destructive,
  success,

  /// Tinted, low-contrast fill derived from the intent color.
  soft,

  /// Text-only, underlined on hover.
  link,
}

/// Semantic meaning. Drives color, default icon and default copy.
enum UiIntent {
  neutral,
  primary,
  bullish,
  bearish,
  warning,
  info,
  success,
  danger,
}

/// How tightly a component packs its content.
enum UiDensity { compact, comfortable, spacious }

/// Generic lifecycle for any data-driven component.
enum UiStatus { idle, loading, empty, error, ready }

/// Validation state for inputs.
enum UiValidationState { none, invalid, valid, warning }

/// Layout orientation used by groups, tabs, steppers, timelines.
enum UiOrientation { horizontal, vertical }

/// Alignment shorthand for slot-based components.
enum UiAlign { start, center, end, between }

extension UiDensityX on UiDensity {
  /// Multiplier applied to internal padding / gaps.
  double get factor {
    switch (this) {
      case UiDensity.compact:
        return 0.72;
      case UiDensity.comfortable:
        return 1;
      case UiDensity.spacious:
        return 1.35;
    }
  }

  String get label {
    switch (this) {
      case UiDensity.compact:
        return 'Compact';
      case UiDensity.comfortable:
        return 'Comfortable';
      case UiDensity.spacious:
        return 'Spacious';
    }
  }
}

extension UiSizeX on UiSize {
  double height(BuildContext context) {
    final s = context.uiSizes;
    switch (this) {
      case UiSize.xs:
        return context.sz(s.controlHeightXs);
      case UiSize.sm:
        return context.sz(s.controlHeightSm);
      case UiSize.md:
        return context.sz(s.controlHeightMd);
      case UiSize.lg:
        return context.sz(s.controlHeightLg);
      case UiSize.xl:
        return context.sz(s.controlHeightXl);
    }
  }

  double icon(BuildContext context) {
    final s = context.uiSizes;
    switch (this) {
      case UiSize.xs:
        return context.sz(s.iconXs);
      case UiSize.sm:
        return context.sz(s.iconSm);
      case UiSize.md:
        return context.sz(s.iconMd);
      case UiSize.lg:
        return context.sz(s.iconLg);
      case UiSize.xl:
        return context.sz(s.iconXl);
    }
  }

  double avatar(BuildContext context) {
    final s = context.uiSizes;
    switch (this) {
      case UiSize.xs:
        return context.sz(s.avatarXs);
      case UiSize.sm:
        return context.sz(s.avatarSm);
      case UiSize.md:
        return context.sz(s.avatarMd);
      case UiSize.lg:
        return context.sz(s.avatarLg);
      case UiSize.xl:
        return context.sz(s.avatarXl);
    }
  }

  /// Horizontal padding, optionally scaled by [density].
  EdgeInsets padding(
    BuildContext context, {
    UiDensity density = UiDensity.comfortable,
  }) {
    final sp = context.uiSpace;
    final double f = density.factor;
    switch (this) {
      case UiSize.xs:
        return EdgeInsets.symmetric(horizontal: context.sp(sp.sm) * f);
      case UiSize.sm:
        return EdgeInsets.symmetric(horizontal: context.sp(sp.md) * f);
      case UiSize.md:
        return EdgeInsets.symmetric(horizontal: context.sp(sp.lg) * f);
      case UiSize.lg:
        return EdgeInsets.symmetric(horizontal: context.sp(sp.xl) * f);
      case UiSize.xl:
        return EdgeInsets.symmetric(horizontal: context.sp(sp.xxl) * f);
    }
  }

  /// Inner gap between icon and label.
  double gap(BuildContext context, {UiDensity density = UiDensity.comfortable}) {
    final sp = context.uiSpace;
    final double f = density.factor;
    switch (this) {
      case UiSize.xs:
      case UiSize.sm:
        return context.sp(sp.xs) * f;
      case UiSize.md:
        return context.sp(sp.sm) * f;
      case UiSize.lg:
      case UiSize.xl:
        return context.sp(sp.md) * f;
    }
  }

  double radius(BuildContext context) {
    final r = context.ui.radii;
    switch (this) {
      case UiSize.xs:
        return r.sm;
      case UiSize.sm:
        return r.md;
      case UiSize.md:
        return r.lg;
      case UiSize.lg:
        return r.lg;
      case UiSize.xl:
        return r.xl;
    }
  }

  TextStyle textStyle(BuildContext context) {
    final t = context.uiText;
    switch (this) {
      case UiSize.xs:
        return t.caption;
      case UiSize.sm:
        return t.label;
      case UiSize.md:
        return t.bodyStrong;
      case UiSize.lg:
        return t.subheading;
      case UiSize.xl:
        return t.heading;
    }
  }

  String get label {
    switch (this) {
      case UiSize.xs:
        return 'xs';
      case UiSize.sm:
        return 'sm';
      case UiSize.md:
        return 'md';
      case UiSize.lg:
        return 'lg';
      case UiSize.xl:
        return 'xl';
    }
  }
}

extension UiIntentX on UiIntent {
  Color color(BuildContext context) {
    final c = context.uiColors;
    switch (this) {
      case UiIntent.neutral:
        return c.foregroundMuted;
      case UiIntent.primary:
        return c.primary;
      case UiIntent.bullish:
      case UiIntent.success:
        return c.bullish;
      case UiIntent.bearish:
      case UiIntent.danger:
        return c.bearish;
      case UiIntent.warning:
        return c.warning;
      case UiIntent.info:
        return c.info;
    }
  }

  /// Readable foreground when [color] is used as a solid fill.
  Color onColor(BuildContext context) {
    final c = context.uiColors;
    switch (this) {
      case UiIntent.primary:
        return c.onPrimary;
      case UiIntent.neutral:
        return c.surface;
      default:
        return c.onDestructive;
    }
  }

  Color surface(BuildContext context, {double alpha = 0.12}) =>
      color(context).withValues(alpha: alpha);

  Color border(BuildContext context, {double alpha = 0.32}) =>
      color(context).withValues(alpha: alpha);

  IconData get icon {
    switch (this) {
      case UiIntent.bullish:
      case UiIntent.success:
        return Icons.check_circle_outline;
      case UiIntent.bearish:
      case UiIntent.danger:
        return Icons.error_outline;
      case UiIntent.warning:
        return Icons.warning_amber_outlined;
      case UiIntent.info:
      case UiIntent.primary:
      case UiIntent.neutral:
        return Icons.info_outline;
    }
  }

  String get label {
    switch (this) {
      case UiIntent.neutral:
        return 'Neutral';
      case UiIntent.primary:
        return 'Primary';
      case UiIntent.bullish:
        return 'Bullish';
      case UiIntent.bearish:
        return 'Bearish';
      case UiIntent.warning:
        return 'Warning';
      case UiIntent.info:
        return 'Info';
      case UiIntent.success:
        return 'Success';
      case UiIntent.danger:
        return 'Danger';
    }
  }
}

/// Snapshot of pointer / focus state handed to builders.
class UiInteractiveState {
  const UiInteractiveState({
    required this.hovered,
    required this.pressed,
    required this.focused,
    required this.enabled,
    this.selected = false,
  });

  final bool hovered;
  final bool pressed;
  final bool focused;
  final bool enabled;
  final bool selected;

  bool get active => hovered || pressed;

  UiInteractiveState copyWith({
    bool? hovered,
    bool? pressed,
    bool? focused,
    bool? enabled,
    bool? selected,
  }) =>
      UiInteractiveState(
        hovered: hovered ?? this.hovered,
        pressed: pressed ?? this.pressed,
        focused: focused ?? this.focused,
        enabled: enabled ?? this.enabled,
        selected: selected ?? this.selected,
      );
}

/// Wraps a child with hover / press / focus state without any styling opinion.
///
/// [forceState] lets a gallery or test render a specific visual state without
/// simulating real pointer input.
class UiInteractive extends StatefulWidget {
  const UiInteractive({
    super.key,
    required this.builder,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.onHoverChanged,
    this.onFocusChanged,
    this.enabled = true,
    this.selected = false,
    this.cursor = SystemMouseCursors.click,
    this.borderRadius,
    this.semanticLabel,
    this.tooltip,
    this.focusNode,
    this.autofocus = false,
    this.forceState,
  });

  final Widget Function(BuildContext context, UiInteractiveState state) builder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;
  final bool enabled;
  final bool selected;
  final MouseCursor cursor;
  final BorderRadius? borderRadius;
  final String? semanticLabel;
  final String? tooltip;
  final FocusNode? focusNode;
  final bool autofocus;
  final UiInteractiveState? forceState;

  @override
  State<UiInteractive> createState() => _UiInteractiveState();
}

class _UiInteractiveState extends State<UiInteractive> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _setHover(bool v) {
    if (_hovered == v) return;
    setState(() => _hovered = v);
    widget.onHoverChanged?.call(v);
  }

  void _setFocus(bool v) {
    if (_focused == v) return;
    setState(() => _focused = v);
    widget.onFocusChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final bool tappable =
        widget.enabled && (widget.onTap != null || widget.onLongPress != null);
    final UiInteractiveState state = widget.forceState ??
        UiInteractiveState(
          hovered: _hovered,
          pressed: _pressed,
          focused: _focused,
          enabled: widget.enabled,
          selected: widget.selected,
        );

    Widget child = Semantics(
      button: widget.onTap != null,
      label: widget.semanticLabel,
      enabled: widget.enabled,
      selected: widget.selected,
      child: FocusableActionDetector(
        enabled: widget.enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        mouseCursor:
            widget.enabled ? widget.cursor : SystemMouseCursors.forbidden,
        onShowHoverHighlight: _setHover,
        onShowFocusHighlight: _setFocus,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              if (widget.enabled) widget.onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? widget.onTap : null,
          onLongPress: widget.enabled ? widget.onLongPress : null,
          onSecondaryTap: widget.enabled ? widget.onSecondaryTap : null,
          onTapDown: tappable ? (_) => setState(() => _pressed = true) : null,
          onTapUp: tappable ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: tappable ? () => setState(() => _pressed = false) : null,
          child: widget.builder(context, state),
        ),
      ),
    );

    if (widget.tooltip != null) {
      child = Tooltip(message: widget.tooltip!, child: child);
    }
    return child;
  }
}

/// Focus ring decoration derived from tokens.
BoxDecoration uiFocusRing(
  BuildContext context,
  BorderRadius radius, {
  Color? color,
}) =>
    BoxDecoration(
      borderRadius: radius,
      border: Border.all(
        color: color ?? context.uiColors.focusRing,
        width: context.ui.borders.focus,
      ),
    );

/// Soft outer glow used for emphasis surfaces (primary buttons, active cards).
List<BoxShadow> uiGlow(BuildContext context, Color color, {double alpha = 0.28}) =>
    <BoxShadow>[
      BoxShadow(
        color: color.withValues(alpha: alpha),
        blurRadius: context.sz(18),
        offset: Offset(0, context.sz(6)),
      ),
    ];

/// Subtle top-lit gradient applied to elevated surfaces.
LinearGradient uiSurfaceGradient(Color base, {double lift = 0.05}) =>
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        Color.alphaBlend(Colors.white.withValues(alpha: lift), base),
        base,
      ],
    );

/// Number formatting helpers used by charts / lists (no intl dependency).
typedef UiValueFormatter = String Function(num value);

String uiCompactNumber(num value) {
  final double v = value.toDouble();
  final double abs = v.abs();
  if (abs >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
  if (abs >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (abs >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  if (abs >= 100) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

String uiSignedPercent(num value, {int decimals = 2}) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(decimals)}%';

String uiSignedNumber(num value, {int decimals = 2}) =>
    '${value >= 0 ? '+' : ''}${value.toStringAsFixed(decimals)}';

/// Groups digits with [groupSeparator]; currency symbol is caller-supplied so
/// no locale or symbol is ever hardcoded inside a component.
String uiGrouped(
  num value, {
  int decimals = 2,
  String groupSeparator = ',',
  String prefix = '',
  String suffix = '',
  bool signed = false,
}) {
  final bool negative = value < 0;
  final String fixed = value.abs().toStringAsFixed(decimals);
  final List<String> parts = fixed.split('.');
  final String whole = parts.first;
  final StringBuffer out = StringBuffer();
  for (int i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(groupSeparator);
    out.write(whole[i]);
  }
  final String body =
      parts.length > 1 ? '$out.${parts[1]}' : out.toString();
  final String sign = negative ? '-' : (signed ? '+' : '');
  return '$sign$prefix$body$suffix';
}

/// Clamps a double without importing dart:math at every call site.
double uiClamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);
