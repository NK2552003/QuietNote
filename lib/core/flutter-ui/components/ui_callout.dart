import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Inline informational banner (risk warnings, market-closed notices).
class UiCallout extends StatelessWidget {
  const UiCallout({
    super.key,
    required this.title,
    this.message,
    this.intent = UiIntent.info,
    this.icon,
    this.onClose,
    this.action,
  });

  final String title;
  final String? message;
  final UiIntent intent;
  final IconData? icon;
  final VoidCallback? onClose;
  final Widget? action;

  IconData get _defaultIcon => intent.icon;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color base = intent.color(context);
    return Container(
      padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
      decoration: BoxDecoration(
        color: base.withValues(alpha: 0.08),
        borderRadius: context.radius(theme.radii.lg),
        border: Border.all(
          color: base.withValues(alpha: 0.28),
          width: theme.borders.hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            icon ?? _defaultIcon,
            color: base,
            size: context.sz(theme.sizes.iconMd),
          ),
          SizedBox(width: context.sp(theme.spacing.md)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: context.uiText.bodyStrong.copyWith(color: base),
                ),
                if (message != null) ...<Widget>[
                  SizedBox(height: context.sp(theme.spacing.xs)),
                  Text(
                    message!,
                    style: context.uiText.body
                        .copyWith(color: theme.colors.foregroundMuted),
                  ),
                ],
                if (action != null) ...<Widget>[
                  SizedBox(height: context.sp(theme.spacing.md)),
                  action!,
                ],
              ],
            ),
          ),
          if (onClose != null)
            GestureDetector(
              onTap: onClose,
              child: Icon(
                Icons.close,
                size: context.sz(theme.sizes.iconSm),
                color: theme.colors.foregroundSubtle,
              ),
            ),
        ],
      ),
    );
  }
}
