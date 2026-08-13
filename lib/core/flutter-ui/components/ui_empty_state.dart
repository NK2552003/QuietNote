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
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double screenHeight = MediaQuery.sizeOf(context).height;
    final double minHeight = (screenHeight - 360).clamp(220.0, 600.0);

    return Container(
      constraints: compact ? null : BoxConstraints(minHeight: minHeight),
      padding: EdgeInsets.symmetric(
        horizontal: context.sp(theme.spacing.xl),
        vertical: context.sp(compact ? theme.spacing.xl : theme.spacing.lg),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colors.surfaceMuted,
              border: Border.all(
                color: theme.colors.border,
                width: theme.borders.hairline,
              ),
            ),
            child: Icon(
              icon,
              size: 32,
              color: theme.colors.foregroundMuted,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: context.uiText.subheading.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: theme.colors.foreground,
            ),
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: context.uiText.body.copyWith(
                fontSize: 13,
                color: theme.colors.foregroundMuted,
              ),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 16),
            action!,
          ],
        ],
      ),
    );
  }
}
