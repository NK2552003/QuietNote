import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Empty state block used by feeds, watchlists and search results.
class UiEmptyState extends StatelessWidget {
  const UiEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Padding(
      padding: EdgeInsets.all(context.sp(theme.spacing.xxl)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colors.surfaceMuted,
            ),
            child: Icon(
              icon,
              size: context.sz(theme.sizes.iconLg),
              color: theme.colors.foregroundSubtle,
            ),
          ),
          SizedBox(height: context.sp(theme.spacing.lg)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.uiText.subheading
                .copyWith(color: theme.colors.foreground),
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: context.sp(theme.spacing.xs)),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.uiText.body
                  .copyWith(color: theme.colors.foregroundMuted),
            ),
          ],
          if (action != null) ...<Widget>[
            SizedBox(height: context.sp(theme.spacing.lg)),
            action!,
          ],
        ],
      ),
    );
  }
}
