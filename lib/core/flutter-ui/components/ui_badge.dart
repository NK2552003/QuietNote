import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Badge shape treatments.
enum UiBadgeVariant { soft, solid, outline, dot, ghost }

/// Status / tag chip. Also covers price-change deltas used in market lists,
/// removable filter chips, dot indicators and counters.
class UiBadge extends StatelessWidget {
  const UiBadge({
    super.key,
    required this.label,
    this.intent = UiIntent.neutral,
    this.size = UiSize.sm,
    this.variant = UiBadgeVariant.soft,
    this.icon,
    this.trailingIcon,
    this.filled = false,
    this.uppercase = false,
    this.pulse = false,
    this.showDot = false,
    this.maxWidth,
    this.tooltip,
    this.onTap,
    this.onRemove,
  });

  /// Convenience for "+2.43%" / "-1.10%" market deltas.
  factory UiBadge.delta(
    num percent, {
    Key? key,
    UiSize size = UiSize.sm,
    int decimals = 2,
    UiBadgeVariant variant = UiBadgeVariant.soft,
    bool showIcon = true,
  }) =>
      UiBadge(
        key: key,
        label: uiSignedPercent(percent, decimals: decimals),
        intent: percent >= 0 ? UiIntent.bullish : UiIntent.bearish,
        icon: showIcon
            ? (percent >= 0 ? Icons.trending_up : Icons.trending_down)
            : null,
        variant: variant,
        size: size,
      );

  /// Compact numeric counter, e.g. unread notifications.
  factory UiBadge.count(
    int count, {
    Key? key,
    int max = 99,
    UiIntent intent = UiIntent.primary,
    UiSize size = UiSize.xs,
  }) =>
      UiBadge(
        key: key,
        label: count > max ? '$max+' : '$count',
        intent: intent,
        size: size,
        variant: UiBadgeVariant.solid,
      );

  /// Live status pill with a leading dot.
  factory UiBadge.status(
    String label, {
    Key? key,
    UiIntent intent = UiIntent.bullish,
    UiSize size = UiSize.sm,
    bool pulse = true,
  }) =>
      UiBadge(
        key: key,
        label: label,
        intent: intent,
        size: size,
        showDot: true,
        pulse: pulse,
      );

  final String label;
  final UiIntent intent;
  final UiSize size;
  final UiBadgeVariant variant;
  final IconData? icon;
  final IconData? trailingIcon;

  /// Legacy flag kept for source compatibility — equivalent to
  /// [UiBadgeVariant.solid].
  final bool filled;
  final bool uppercase;

  /// Animates the leading dot (live / streaming states).
  final bool pulse;
  final bool showDot;
  final double? maxWidth;
  final String? tooltip;
  final VoidCallback? onTap;

  /// Renders a trailing close affordance (filter chips).
  final VoidCallback? onRemove;

  UiBadgeVariant get _variant =>
      filled ? UiBadgeVariant.solid : variant;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color base = intent.color(context);
    final BorderRadius radius = context.radius(theme.radii.pill);
    final bool solid = _variant == UiBadgeVariant.solid;

    final Color fg = solid ? intent.onColor(context) : base;
    final TextStyle textStyle = (size == UiSize.xs || size == UiSize.sm
            ? context.uiText.caption
            : context.uiText.label)
        .copyWith(
      color: fg,
      fontWeight: FontWeight.w600,
      letterSpacing: uppercase ? 0.6 : null,
    );

    Color background;
    Color borderColor;
    switch (_variant) {
      case UiBadgeVariant.solid:
        background = base;
        borderColor = Colors.transparent;
        break;
      case UiBadgeVariant.outline:
        background = Colors.transparent;
        borderColor = base.withValues(alpha: 0.5);
        break;
      case UiBadgeVariant.ghost:
      case UiBadgeVariant.dot:
        background = Colors.transparent;
        borderColor = Colors.transparent;
        break;
      case UiBadgeVariant.soft:
        background = base.withValues(alpha: 0.12);
        borderColor = base.withValues(alpha: 0.3);
        break;
    }

    final double iconSize = size.icon(context) * 0.85;
    final Widget chip = AnimatedContainer(
      duration: theme.motion.fast,
      curve: theme.motion.curve,
      constraints:
          maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      padding: EdgeInsets.symmetric(
        horizontal: context.sp(
          _variant == UiBadgeVariant.dot ? theme.spacing.xxs : theme.spacing.sm,
        ),
        vertical: context.sp(theme.spacing.xxs),
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: borderColor, width: theme.borders.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showDot || _variant == UiBadgeVariant.dot) ...<Widget>[
            _Dot(color: solid ? fg : base, pulse: pulse, size: iconSize * 0.5),
            SizedBox(width: context.sp(theme.spacing.xs)),
          ],
          if (icon != null) ...<Widget>[
            Icon(icon, size: iconSize, color: fg),
            SizedBox(width: context.sp(theme.spacing.xxs)),
          ],
          Flexible(
            child: Text(
              uppercase ? label.toUpperCase() : label,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
          ),
          if (trailingIcon != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xxs)),
            Icon(trailingIcon, size: iconSize, color: fg),
          ],
          if (onRemove != null) ...<Widget>[
            SizedBox(width: context.sp(theme.spacing.xxs)),
            UiInteractive(
              onTap: onRemove,
              semanticLabel: 'Remove $label',
              builder: (_, _) => Icon(Icons.close, size: iconSize, color: fg),
            ),
          ],
        ],
      ),
    );

    Widget result = chip;
    if (onTap != null) {
      result = UiInteractive(
        onTap: onTap,
        semanticLabel: label,
        builder: (_, UiInteractiveState s) => Opacity(
          opacity: s.active ? 0.85 : 1,
          child: chip,
        ),
      );
    }
    if (tooltip != null) result = Tooltip(message: tooltip!, child: result);
    return result;
  }
}

class _Dot extends StatefulWidget {
  const _Dot({required this.color, required this.pulse, required this.size});

  final Color color;
  final bool pulse;
  final double size;

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Dot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: dot,
    );
  }
}
