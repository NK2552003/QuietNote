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
  });

  final Widget child;
  final Widget? header;
  final bool scrollable;
  final double? maxWidth;

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
      // every scrollable screen remain reachable.
      bottom: viewPadding.bottom +
          mq.viewInsets.bottom +
          context.sp(r.isMobile ? 96 : theme.spacing.md),
    );

    // Align content to the top and allow it to expand vertically. Using
    // Alignment.topCenter avoids centering the page in the viewport which
    // could make pages appear blank in some embedder states.
    Widget body = SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxWidth ?? context.sz(theme.sizes.maxContentWidth),
          ),
          child: Column(
            mainAxisSize: scrollable ? MainAxisSize.min : MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (header != null) ...<Widget>[
                header!,
                SizedBox(height: context.sp(theme.spacing.lg)),
              ],
              child,
            ],
          ),
        ),
      ),
    );

    body = Padding(padding: pad, child: body);

    // Wrap with a SafeArea so the top header always respects the status
    // bar / notch area. We intentionally keep bottom=false so the page
    // content can still control bottom spacing independently (the
    // navigation shell already wraps the bottom navbar with SafeArea).
    final Widget safe = SafeArea(top: true, bottom: false, child: body);

    return Material(
      color: theme.colors.background,
      child: scrollable
          ? SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: safe,
            )
          : AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
              child: safe,
            ),
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
                style: context.uiText.subheading.copyWith(
                  fontWeight: FontWeight.bold,
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
