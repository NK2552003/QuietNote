import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_card.dart';
import 'ui_common.dart';

/// KPI / metric tile built on [UiCard]; used for portfolio stats.
class UiMetricCard extends StatelessWidget {
  const UiMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.delta,
    this.icon,
    this.chart,
    this.onTap,
  });

  final String label;
  final String value;
  final num? delta;
  final IconData? icon;
  final Widget? chart;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final Color deltaColor = delta == null
        ? theme.colors.foregroundMuted
        : (delta! >= 0 ? theme.colors.bullish : theme.colors.bearish);
    return UiCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: context.sz(theme.sizes.iconSm),
                  color: theme.colors.foregroundMuted,
                ),
                SizedBox(width: context.sp(theme.spacing.xs)),
              ],
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.label
                      .copyWith(color: theme.colors.foregroundMuted),
                ),
              ),
            ],
          ),
          SizedBox(height: context.sp(theme.spacing.sm)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.title
                      .copyWith(color: theme.colors.foreground),
                ),
              ),
              if (delta != null)
                Text(
                  uiSignedPercent(delta!),
                  style: context.uiText.bodyStrong.copyWith(color: deltaColor),
                ),
            ],
          ),
          if (chart != null) ...<Widget>[
            SizedBox(height: context.sp(theme.spacing.md)),
            SizedBox(
              height: context.sz(theme.sizes.sparkHeight),
              child: chart,
            ),
          ],
        ],
      ),
    );
  }
}
