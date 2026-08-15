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
    this.dynamicHeight = false,
  });

  final List<Widget> children;
  final int mobileColumns;
  final int tabletColumns;
  final int desktopColumns;
  final int largeColumns;
  final double childAspectRatio;

  /// A fixed card height. Use this for content previews so a wider screen
  /// never makes tiles taller (or shorter). Ignored when [dynamicHeight] is
  /// true — the two are mutually exclusive ways of controlling tile height.
  final double? mainAxisExtent;

  /// Lets tiles choose their column count from the available width. This is
  /// useful for preview cards: they stay comfortably readable on narrow
  /// screens while avoiding needlessly wide cards on larger layouts.
  final double? maxCrossAxisExtent;

  /// When true, every tile is exactly as tall as its own content instead of
  /// every tile in a row sharing one fixed height. `GridView` can't do this
  /// itself — every cell in a `SliverGridDelegateWithFixedCrossAxisCount`
  /// row is forced to the same `mainAxisExtent`, and with an odd number of
  /// tiles the last row's empty cell renders as a visible blank gap next to
  /// the final card. This mode sidesteps `GridView` entirely: children are
  /// dealt round-robin into [mobileColumns]/etc. independent columns, each
  /// one a plain `Column` that simply wraps its own cards, so every card is
  /// its natural height and nothing is ever forced to match a neighbour or
  /// leaves a gap behind.
  final bool dynamicHeight;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = context.sp(theme.spacing.lg);
        final int columns = _columnCount(constraints.maxWidth);

        if (dynamicHeight) {
          return _MasonryLayout(columns: columns, gap: gap, children: children);
        }

        final gridDelegate = maxCrossAxisExtent == null
            ? SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
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

/// Deals [children] round-robin into [columns] independent vertical stacks.
/// With `columns == 1` this is just a plain top-to-bottom list — exactly
/// "one column, one row per card" — and every card above that is free to be
/// whatever height its own content needs.
class _MasonryLayout extends StatelessWidget {
  const _MasonryLayout({
    required this.columns,
    required this.gap,
    required this.children,
  });

  final int columns;
  final double gap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    // Defensive floor: a caller could in principle wire a 0-or-negative
    // column count through the responsive breakpoints; without this a `% 0`
    // below would throw and take the whole screen down with it.
    final int safeColumns = columns < 1 ? 1 : columns;

    if (safeColumns == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    }

    final List<List<Widget>> lanes = List.generate(safeColumns, (_) => <Widget>[]);
    for (int i = 0; i < children.length; i++) {
      lanes[i % safeColumns].add(children[i]);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int c = 0; c < safeColumns; c++) ...[
          if (c > 0) SizedBox(width: gap),
          Expanded(
            child: Column(
              // MainAxisSize.min matters here: this sits inside a Row inside
              // a LayoutBuilder inside a scrolling parent, so the incoming
              // height constraint is unbounded — MainAxisSize.max (Column's
              // default) would then throw trying to be "as tall as possible"
              // in an infinite space. `.min` makes each lane exactly as tall
              // as the cards stacked in it, which is the whole point.
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < lanes[c].length; i++) ...[
                  if (i > 0) SizedBox(height: gap),
                  lanes[c][i],
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
