import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_toaster.dart';

/// Toast visual. Use [UiToast.show] from anywhere with a context.
class UiToast extends StatelessWidget {
  const UiToast({super.key, required this.data, this.onDismiss});

  final UiToastData data;
  final VoidCallback? onDismiss;

  static void show(
    BuildContext context, {
    required String title,
    String? message,
    UiIntent intent = UiIntent.neutral,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) =>
      UiToastScope.of(context).show(
        UiToastData(
          title: title,
          message: message,
          intent: intent,
          icon: icon,
          actionLabel: actionLabel,
          onAction: onAction,
          duration: duration,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color accent = data.intent.color(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: context.sz(380)),
      child: Container(
        padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
        decoration: BoxDecoration(
          color: theme.colors.surface,
          borderRadius: context.radius(theme.radii.lg),
          border: Border.all(
            color: theme.colors.border,
            width: theme.borders.hairline,
          ),
          boxShadow: theme.shadows.lg,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: context.sz(3),
              height: context.sz(theme.sizes.iconLg),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: context.radius(theme.radii.pill),
              ),
            ),
            SizedBox(width: context.sp(theme.spacing.md)),
            if (data.icon != null) ...<Widget>[
              Icon(
                data.icon,
                color: accent,
                size: context.sz(theme.sizes.iconMd),
              ),
              SizedBox(width: context.sp(theme.spacing.sm)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    data.title,
                    style: context.uiText.bodyStrong.copyWith(
                      color: theme.colors.foreground,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  if (data.message != null) ...<Widget>[
                    SizedBox(height: context.sp(theme.spacing.xxs)),
                    Text(
                      data.message!,
                      style: context.uiText.caption.copyWith(
                        color: theme.colors.foregroundMuted,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                  if (data.actionLabel != null) ...<Widget>[
                    SizedBox(height: context.sp(theme.spacing.sm)),
                    GestureDetector(
                      onTap: () {
                        data.onAction?.call();
                        onDismiss?.call();
                      },
                      child: Text(
                        data.actionLabel!,
                        style: context.uiText.label.copyWith(
                          color: theme.colors.primary,
                          fontWeight: FontWeight.w600,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: onDismiss,
              child: Icon(
                Icons.close,
                size: context.sz(theme.sizes.iconSm),
                color: theme.colors.foregroundSubtle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
