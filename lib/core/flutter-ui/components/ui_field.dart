import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_label.dart';

/// Wraps any input with label / helper / validation message / counter, so all
/// form rows align regardless of the control inside.
///
/// Supports stacked (default) and inline (label beside control) layouts,
/// required markers, optional hints, tooltips and a trailing header action.
class UiField extends StatelessWidget {
  const UiField({
    super.key,
    required this.child,
    this.label,
    this.helper,
    this.error,
    this.warning,
    this.success,
    this.required = false,
    this.optionalLabel,
    this.tooltip,
    this.headerAction,
    this.orientation = UiOrientation.vertical,
    this.labelWidth = 160,
    this.density = UiDensity.comfortable,
    this.counter,
    this.enabled = true,
  });

  final Widget child;
  final String? label;
  final String? helper;

  /// Invalid message — takes precedence over [warning], [success], [helper].
  final String? error;
  final String? warning;
  final String? success;
  final bool required;

  /// Shown next to the label when the field is not required, e.g. "Optional".
  final String? optionalLabel;
  final String? tooltip;

  /// Trailing widget in the label row (e.g. "Forgot password?").
  final Widget? headerAction;

  /// Vertical stacks label above control; horizontal renders them side by side
  /// on tablet/desktop and falls back to vertical on mobile.
  final UiOrientation orientation;
  final double labelWidth;
  final UiDensity density;

  /// Right-aligned counter text under the control, e.g. "12/280".
  final String? counter;
  final bool enabled;

  ({String text, Color color, IconData icon})? _message(BuildContext context) {
    final c = context.uiColors;
    if (error != null) {
      return (text: error!, color: c.destructive, icon: Icons.error_outline);
    }
    if (warning != null) {
      return (
        text: warning!,
        color: c.warning,
        icon: Icons.warning_amber_rounded
      );
    }
    if (success != null) {
      return (
        text: success!,
        color: UiIntent.success.color(context),
        icon: Icons.check_circle_outline
      );
    }
    if (helper != null) {
      return (text: helper!, color: c.foregroundMuted, icon: Icons.info_outline);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double f = density.factor;
    final double gap = context.sp(theme.spacing.xs) * f;
    final bool inline =
        orientation == UiOrientation.horizontal && !context.uiRes.isMobile;
    final msg = _message(context);

    final Widget header = Row(
      children: <Widget>[
        Flexible(
          child: UiLabel(text: label ?? '', required: required),
        ),
        if (optionalLabel != null && !required) ...<Widget>[
          SizedBox(width: context.sp(theme.spacing.xs)),
          Text(
            optionalLabel!,
            style: context.uiText.caption
                .copyWith(color: theme.colors.foregroundSubtle),
          ),
        ],
        if (tooltip != null) ...<Widget>[
          SizedBox(width: context.sp(theme.spacing.xxs)),
          Tooltip(
            message: tooltip!,
            child: Icon(
              Icons.help_outline,
              size: context.sz(theme.sizes.iconSm),
              color: theme.colors.foregroundSubtle,
            ),
          ),
        ],
        if (headerAction != null) ...<Widget>[
          const Spacer(),
          headerAction!,
        ],
      ],
    );

    final Widget footer = (msg == null && counter == null)
        ? const SizedBox.shrink()
        : Padding(
            padding: EdgeInsets.only(top: gap),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (msg != null) ...<Widget>[
                  Icon(msg.icon, size: context.sz(theme.sizes.iconXs), color: msg.color),
                  SizedBox(width: context.sp(theme.spacing.xxs)),
                  Expanded(
                    child: Text(
                      msg.text,
                      style: context.uiText.caption.copyWith(color: msg.color),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (counter != null) ...<Widget>[
                  SizedBox(width: context.sp(theme.spacing.sm)),
                  Text(
                    counter!,
                    style: context.uiText.caption
                        .copyWith(color: theme.colors.foregroundSubtle),
                  ),
                ],
              ],
            ),
          );

    final Widget content = Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[child, footer],
      ),
    );

    if (label == null) return content;

    if (inline) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: context.sz(labelWidth),
            child: Padding(
              padding: EdgeInsets.only(top: gap),
              child: header,
            ),
          ),
          SizedBox(width: context.sp(theme.spacing.lg)),
          Expanded(child: content),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        header,
        SizedBox(height: gap),
        content,
      ],
    );
  }
}
