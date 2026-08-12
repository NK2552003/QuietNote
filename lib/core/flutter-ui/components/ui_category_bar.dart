import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

class UiCategorySegment {
  const UiCategorySegment({
    required this.value,
    required this.label,
    this.color,
  });

  final double value;
  final String label;
  final Color? color;
}

/// Stacked proportional bar (portfolio allocation, sentiment split).
class UiCategoryBar extends StatelessWidget {
  const UiCategoryBar({
    super.key,
    required this.segments,
    this.marker,
    this.showLegend = true,
    this.thickness,
  });

  final List<UiCategorySegment> segments;

  /// 0..1 position of the pointer (e.g. current price within a range).
  final double? marker;
  final bool showLegend;
  final double? thickness;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double total =
        segments.fold<double>(0, (double a, UiCategorySegment s) => a + s.value);
    final double h = context.sz(thickness ?? theme.sizes.trackThickness);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            ClipRRect(
              borderRadius: context.radius(theme.radii.pill),
              child: SizedBox(
                height: h,
                child: Row(
                  children: <Widget>[
                    for (int i = 0; i < segments.length; i++)
                      Expanded(
                        flex: total == 0
                            ? 1
                            : (segments[i].value / total * 1000).round().clamp(1, 1000),
                        child: ColoredBox(
                          color: segments[i].color ??
                              theme.colors.series[i % theme.colors.series.length],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (marker != null)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: marker!.clamp(0, 1),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      width: context.sz(3),
                      height: h * 2,
                      decoration: BoxDecoration(
                        color: theme.colors.foreground,
                        borderRadius: context.radius(theme.radii.pill),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (showLegend) ...<Widget>[
          SizedBox(height: context.sp(theme.spacing.md)),
          Wrap(
            spacing: context.sp(theme.spacing.lg),
            runSpacing: context.sp(theme.spacing.xs),
            children: <Widget>[
              for (int i = 0; i < segments.length; i++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Container(
                      width: context.sz(8),
                      height: context.sz(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: segments[i].color ??
                            theme.colors.series[i % theme.colors.series.length],
                      ),
                    ),
                    SizedBox(width: context.sp(theme.spacing.xs)),
                    Text(
                      segments[i].label,
                      style: context.uiText.caption
                          .copyWith(color: theme.colors.foregroundMuted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}
