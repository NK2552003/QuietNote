import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';

/// Page scaffold: max content width, responsive padding, optional sticky header.
class UiPage extends StatelessWidget {
  const UiPage({
    super.key,
    required this.child,
    this.header,
    this.scrollable = true,
    this.maxWidth,
    this.floatingActionButton,
    this.reserveDockSpace = true,
  });

  final Widget child;
  final Widget? header;
  final bool scrollable;
  final double? maxWidth;

  /// Optional floating action button, anchored bottom-right. Positioned
  /// above the floating mobile tab bar so it never overlaps it.
  final Widget? floatingActionButton;

  /// Whether the scrollable body's bottom padding and the FAB's bottom
  /// offset should reserve clearance for the floating mobile tab bar dock.
  /// Defaults to `true`, matching every screen that lives inside
  /// [UiNavShell]. Screens reached by pushing a new route outside the
  /// shell (e.g. a note/journal preview or editor) render with no dock
  /// present at all, so reserving space for it just leaves a dead gap and
  /// pushes their own FAB up into it — those screens pass `false`.
  final bool reserveDockSpace;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final r = context.uiRes;
    // Use MediaQuery view padding to properly account for system UI like
    // status bars and bottom navigation bars. Avoid reading the
    // platform dispatcher directly which can yield unexpected zero
    // metrics during some embedder states.
    final mq = MediaQuery.of(context);
    final viewPadding = mq.viewPadding;

    final EdgeInsets pad = EdgeInsets.only(
      left: context.sp(
        r.pick<double>(
          mobile: theme.spacing.sm,
          tablet: theme.spacing.md,
          desktop: theme.spacing.lg,
        ),
      ),
      right: context.sp(
        r.pick<double>(
          mobile: theme.spacing.sm,
          tablet: theme.spacing.md,
          desktop: theme.spacing.lg,
        ),
      ),
      // We now use SafeArea to handle the top system inset for headers.
      // Keep a modest internal top/bottom spacing for visual rhythm.
      top: context.sp(theme.spacing.sm),
      // The floating mobile tab bar overlays the body. Reserve enough space
      // for it (plus the gesture inset) so the final fields and buttons on
      // every scrollable screen remain reachable — but only on screens that
      // actually render inside the shell where that dock exists.
      bottom: viewPadding.bottom +
          context.sp(
            reserveDockSpace ? (r.isMobile ? 96 : theme.spacing.md) : theme.spacing.md,
          ),
    );

    final double contentMaxWidth = maxWidth ?? context.sz(theme.sizes.maxContentWidth);

    // Centers content and clamps it to the page's max width, without
    // affecting vertical sizing — used for both the fixed header and the
    // scrollable body so they line up.
    Widget wrapMaxWidth(Widget child) {
      return SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: contentMaxWidth),
            child: child,
          ),
        ),
      );
    }

    // The header is deliberately built and laid out *outside* the
    // SingleChildScrollView below, so it stays pinned to the top of the
    // screen — e.g. Back/Preview/Save on an editor — instead of scrolling
    // away with the body. (Previously header and body lived in the same
    // scrollable Column, so a long note/journal entry pushed the header
    // off-screen and required scrolling all the way back up to reach it.)
    final Widget? headerSection = header == null
        ? null
        : SafeArea(
            top: true,
            bottom: false,
            child: Padding(
              // A small bottom inset so the header's own subtitle/word-count
              // line isn't sitting flush against the body content directly
              // below it — the body's own top padding is separately reduced
              // to `theme.spacing.lg` (see below) specifically because a
              // fixed header already handles this gap, so this is the one
              // place that gap actually lives.
              padding: EdgeInsets.fromLTRB(
                pad.left,
                pad.top,
                pad.right,
                context.sp(theme.spacing.xs),
              ),
              child: wrapMaxWidth(header!),
            ),
          );

    Widget bodyContent = wrapMaxWidth(
      Column(
        mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[child],
      ),
    );

    bodyContent = Padding(
      padding: EdgeInsets.only(
        left: pad.left,
        right: pad.right,
        // When there's a fixed header above, only a small visual gap is
        // needed here; the header's own top padding already handled the
        // status-bar inset. Without a header, the body needs that same top
        // padding (and its own SafeArea) since nothing above it provides it.
        top: header != null ? context.sp(theme.spacing.lg) : pad.top,
        bottom: pad.bottom,
      ),
      child: bodyContent,
    );

    if (header == null) {
      bodyContent = SafeArea(top: true, bottom: false, child: bodyContent);
    }

    final Widget scrollableBody = scrollable
        ? SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: bodyContent,
          )
        : bodyContent;

    final Widget page = Material(
      color: theme.colors.background,
      child: Column(
        children: <Widget>[
          if (headerSection != null) headerSection,
          Expanded(
            child: AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: scrollableBody,
            ),
          ),
        ],
      ),
    );

    if (floatingActionButton == null) return page;

    // Reserve the same clearance UiPage already gives scrollable content
    // for the floating mobile tab bar, so the FAB always floats just above
    // it instead of overlapping — again, only when that dock is actually
    // present. On a pushed screen with no dock, `reserveDockSpace: false`
    // keeps the FAB anchored to the screen's own bottom edge instead of
    // floating a dock's-worth of empty space above it.
    final double fabBottomInset = viewPadding.bottom +
        mq.viewInsets.bottom +
        context.sp(
          reserveDockSpace ? (r.isMobile ? 96 : theme.spacing.lg) : theme.spacing.md,
        ) +
        5;

    return Stack(
      children: <Widget>[
        page,
        Positioned(
          right: context.sp(theme.spacing.md),
          bottom: fabBottomInset,
          child: floatingActionButton!,
        ),
      ],
    );
  }
}

/// Responsive header row: title + actions that never clip on small widths.
class UiHeader extends StatelessWidget {
  const UiHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          SizedBox(width: context.sp(theme.spacing.sm)),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.uiText.heading.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: theme.colors.foreground,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                SizedBox(height: context.sp(theme.spacing.xxs)),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.uiText.caption.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colors.foregroundMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...<Widget>[
          SizedBox(width: context.sp(theme.spacing.sm)),
          Wrap(spacing: context.sp(theme.spacing.xs), children: actions),
        ],
      ],
    );
  }
}
