import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_icon_button.dart';

/// Page navigation for long lists (saved posts, followers, audit logs).
class UiPagination extends StatelessWidget {
  const UiPagination({
    super.key,
    required this.page,
    required this.pageCount,
    required this.onPageChanged,
    this.totalLabel,
  });

  /// Zero-based page index.
  final int page;
  final int pageCount;
  final ValueChanged<int> onPageChanged;
  final String? totalLabel;

  @override
  Widget build(BuildContext context) {
    final UiTheme theme = context.ui;
    final List<int> pages = <int>[
      for (int i = 0; i < pageCount; i++)
        if (i == 0 ||
            i == pageCount - 1 ||
            (i - page).abs() <= (context.uiRes.isMobile ? 0 : 1))
          i,
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        UiIconButton(
          icon: Icons.chevron_left,
          variant: UiVariant.ghost,
          tooltip: 'Previous',
          onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
        ),
        for (int i = 0; i < pages.length; i++) ...<Widget>[
          if (i > 0 && pages[i] - pages[i - 1] > 1)
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: context.sp(theme.spacing.xs)),
              child: Text(
                '…',
                style: context.uiText.caption
                    .copyWith(color: theme.colors.foregroundSubtle),
              ),
            ),
          UiInteractive(
            onTap: () => onPageChanged(pages[i]),
            builder: (BuildContext ctx, UiInteractiveState s) => Container(
              margin:
                  EdgeInsets.symmetric(horizontal: ctx.sp(theme.spacing.xxs)),
              width: ctx.sz(theme.sizes.controlHeightSm),
              height: ctx.sz(theme.sizes.controlHeightSm),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: pages[i] == page
                    ? theme.colors.primary
                    : (s.hovered ? theme.colors.surfaceHover : null),
                borderRadius: ctx.radius(theme.radii.md),
              ),
              child: Text(
                '${pages[i] + 1}',
                style: ctx.uiText.label.copyWith(
                  color: pages[i] == page
                      ? theme.colors.onPrimary
                      : theme.colors.foregroundMuted,
                ),
              ),
            ),
          ),
        ],
        UiIconButton(
          icon: Icons.chevron_right,
          variant: UiVariant.ghost,
          tooltip: 'Next',
          onPressed:
              page < pageCount - 1 ? () => onPageChanged(page + 1) : null,
        ),
        if (totalLabel != null && !context.uiRes.isMobile) ...<Widget>[
          SizedBox(width: context.sp(theme.spacing.md)),
          Text(
            totalLabel!,
            style: context.uiText.caption
                .copyWith(color: theme.colors.foregroundMuted),
          ),
        ],
      ],
    );
  }
}
