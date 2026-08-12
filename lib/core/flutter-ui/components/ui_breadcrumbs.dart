import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

@immutable
class UiCrumb {
  const UiCrumb({required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
}

/// Desktop breadcrumb trail (Journal / June 2026 / AAPL long).
class UiBreadcrumbs extends StatelessWidget {
  const UiBreadcrumbs({super.key, required this.crumbs});

  final List<UiCrumb> crumbs;

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (int i = 0; i < crumbs.length; i++) ...<Widget>[
          UiInteractive(
            onTap: crumbs[i].onTap,
            builder: (BuildContext ctx, UiInteractiveState s) => Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (crumbs[i].icon != null) ...<Widget>[
                  Icon(
                    crumbs[i].icon,
                    size: ctx.sz(theme.sizes.iconSm),
                    color: theme.colors.foregroundMuted,
                  ),
                  SizedBox(width: ctx.sp(theme.spacing.xxs)),
                ],
                Text(
                  crumbs[i].label,
                  style: i == crumbs.length - 1
                      ? ctx.uiText.label
                      : ctx.uiText.label.copyWith(
                          color: s.hovered
                              ? theme.colors.primary
                              : theme.colors.foregroundMuted,
                        ),
                ),
              ],
            ),
          ),
          if (i != crumbs.length - 1)
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: context.sp(theme.spacing.xs)),
              child: Icon(
                Icons.chevron_right,
                size: context.sz(theme.sizes.iconSm),
                color: theme.colors.foregroundSubtle,
              ),
            ),
        ],
      ],
    );
  }
}
