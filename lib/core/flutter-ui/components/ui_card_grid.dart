import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Responsive card grid: column count comes from the responsive helper.
class UiCardGrid extends StatelessWidget {
  const UiCardGrid({
    super.key,
    required this.children,
    this.mobileColumns = 1,
    this.tabletColumns = 2,
    this.desktopColumns = 3,
    this.largeColumns = 4,
    this.childAspectRatio = 1.6,
    this.mainAxisExtent,
    this.maxCrossAxisExtent,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final int largeColumns;
  final double childAspectRatio;

  /// A fixed card height. Use this for content previews so a wider screen
  /// never makes tiles taller (or shorter).
  final double? mainAxisExtent;

  /// Lets tiles choose their column count from the available width. This is
  /// useful for preview cards: they stay comfortably readable on narrow
  /// screens while avoiding needlessly wide cards on larger layouts.
  final double? maxCrossAxisExtent;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = context.sp(theme.spacing.lg);
        final gridDelegate = maxCrossAxisExtent == null
            ? SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _columnCount(constraints.maxWidth),
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                childAspectRatio: childAspectRatio,
                mainAxisExtent: mainAxisExtent,
              )
            : SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxCrossAxisExtent!,
                mainAxisSpacing: gap,
                crossAxisSpacing: gap,
                childAspectRatio: childAspectRatio,
                mainAxisExtent: mainAxisExtent,
              );
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: children.length,
          gridDelegate: gridDelegate,
          itemBuilder: (BuildContext _, int i) => children[i],
        );
      },
    );
  }

  int _columnCount(double width) {
    if (width < 600) return mobileColumns;
    if (width < 900) return tabletColumns;
    if (width < 1200) return desktopColumns;
    return largeColumns;
  }
}
