import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Horizontal / vertical separator, optionally with centered content.
class UiDivider extends StatelessWidget {
  const UiDivider({
    super.key,
    this.label,
    this.vertical = false,
    this.spacing,
  });

  final String? label;
  final bool vertical;
  final double? spacing;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double gap = context.sp(spacing ?? theme.spacing.lg);

    if (vertical) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gap),
        child: SizedBox(
          width: theme.borders.hairline,
          child: ColoredBox(color: theme.colors.border),
        ),
      );
    }

    final Widget line = Expanded(
      child: Container(
        height: theme.borders.hairline,
        color: theme.colors.border,
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: gap),
      child: label == null
          ? Row(children: <Widget>[line])
          : Row(
              children: <Widget>[
                line,
                Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: context.sp(theme.spacing.md)),
                  child: Text(
                    label!,
                    style: context.uiText.caption
                        .copyWith(color: theme.colors.foregroundSubtle),
                  ),
                ),
                line,
              ],
            ),
    );
  }
}
