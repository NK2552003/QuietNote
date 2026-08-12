import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Form label with optional required marker and helper/error text.
class UiLabel extends StatelessWidget {
  const UiLabel({
    super.key,
    required this.text,
    this.required = false,
    this.disabled = false,
    this.helper,
  });

  final String text;
  final bool required;
  final bool disabled;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color color =
        disabled ? theme.colors.disabledForeground : theme.colors.foreground;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: context.uiText.label.copyWith(color: color),
              ),
            ),
            if (required)
              Text(
                ' *',
                style: context.uiText.label
                    .copyWith(color: theme.colors.destructive),
              ),
          ],
        ),
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
