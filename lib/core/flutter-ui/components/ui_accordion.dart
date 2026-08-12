import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

/// Accordion chrome.
enum UiAccordionVariant {
  /// One bordered container with hairline separators (default).
  contained,

  /// Each item is its own card with a gap between them.
  separated,

  /// No borders at all — headers only.
  ghost,
}

class UiAccordionItem {
  const UiAccordionItem({
    required this.title,
    required this.content,
    this.subtitle,
    this.leadingIcon,
    this.leading,
    this.trailing,
    this.badge,
    this.intent,
    this.enabled = true,
    this.initiallyOpen = false,
  });

  final String title;
  final Widget content;
  final String? subtitle;
  final IconData? leadingIcon;

  /// Replaces the leading icon (avatar, sparkline, status dot).
  final Widget? leading;

  /// Extra widget before the chevron (badge, switch, price).
  final Widget? trailing;
  final String? badge;

  /// Tints the header text/icon and shows an accent stripe.
  final UiIntent? intent;
  final bool enabled;
  final bool initiallyOpen;
}

/// Expand/collapse list. Single or multiple open sections, controlled or
/// uncontrolled, with density, size and variant options.
class UiAccordion extends StatefulWidget {
  const UiAccordion({
    super.key,
    required this.items,
    this.allowMultiple = false,
    this.initiallyOpen = const <int>{},
    this.openIndices,
    this.onChanged,
    this.variant = UiAccordionVariant.contained,
    this.size = UiSize.md,
    this.density = UiDensity.comfortable,
    this.chevronIcon = Icons.keyboard_arrow_down,
    this.chevronLeading = false,
    this.dividers = true,
    this.enabled = true,
  });

  final List<UiAccordionItem> items;
  final bool allowMultiple;
  final Set<int> initiallyOpen;

  /// When provided the accordion is controlled; pair with [onChanged].
  final Set<int>? openIndices;
  final ValueChanged<Set<int>>? onChanged;

  final UiAccordionVariant variant;
  final UiSize size;
  final UiDensity density;
  final IconData chevronIcon;
  final bool chevronLeading;
  final bool dividers;
  final bool enabled;

  @override
  State<UiAccordion> createState() => _UiAccordionState();
}

class _UiAccordionState extends State<UiAccordion> {
  late Set<int> _open = <int>{
    ...widget.initiallyOpen,
    for (int i = 0; i < widget.items.length; i++)
      if (widget.items[i].initiallyOpen) i,
  };

  Set<int> get _effective => widget.openIndices ?? _open;

  void _toggle(int index) {
    final Set<int> next = <int>{..._effective};
    if (next.contains(index)) {
      next.remove(index);
    } else {
      if (!widget.allowMultiple) next.clear();
      next.add(index);
    }
    widget.onChanged?.call(next);
    if (widget.openIndices == null) setState(() => _open = next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final double gap = context.sp(theme.spacing.sm);

    final List<Widget> tiles = <Widget>[
      for (int i = 0; i < widget.items.length; i++)
        _UiAccordionTile(
          item: widget.items[i],
          open: _effective.contains(i),
          size: widget.size,
          density: widget.density,
          variant: widget.variant,
          chevronIcon: widget.chevronIcon,
          chevronLeading: widget.chevronLeading,
          showDivider: widget.dividers &&
              widget.variant == UiAccordionVariant.contained &&
              i != widget.items.length - 1,
          enabled: widget.enabled && widget.items[i].enabled,
          onTap: () => _toggle(i),
        ),
    ];

    switch (widget.variant) {
      case UiAccordionVariant.contained:
        return Container(
          decoration: BoxDecoration(
            color: theme.colors.surface,
            borderRadius: context.radius(theme.radii.lg),
            border: Border.all(
              color: theme.colors.border,
              width: theme.borders.hairline,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: tiles),
        );
      case UiAccordionVariant.separated:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int i = 0; i < tiles.length; i++) ...<Widget>[
              if (i > 0) SizedBox(height: gap),
              Container(
                decoration: BoxDecoration(
                  color: theme.colors.surface,
                  borderRadius: context.radius(theme.radii.lg),
                  border: Border.all(
                    color: theme.colors.border,
                    width: theme.borders.hairline,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: tiles[i],
              ),
            ],
          ],
        );
      case UiAccordionVariant.ghost:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: tiles,
        );
    }
  }
}

class _UiAccordionTile extends StatelessWidget {
  const _UiAccordionTile({
    required this.item,
    required this.open,
    required this.onTap,
    required this.showDivider,
    required this.size,
    required this.density,
    required this.variant,
    required this.chevronIcon,
    required this.chevronLeading,
    required this.enabled,
  });

  final UiAccordionItem item;
  final bool open;
  final VoidCallback onTap;
  final bool showDivider;
  final UiSize size;
  final UiDensity density;
  final UiAccordionVariant variant;
  final IconData chevronIcon;
  final bool chevronLeading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final double f = density.factor;
    final Color? accent = item.intent?.color(context);
    final EdgeInsets pad = EdgeInsets.symmetric(
      horizontal: context.sp(theme.spacing.lg) * f,
      vertical: context.sp(theme.spacing.md) * f,
    );

    final Widget chevron = AnimatedRotation(
      turns: open ? 0.5 : 0,
      duration: theme.motion.normal,
      curve: theme.motion.curve,
      child: Icon(
        chevronIcon,
        size: size.icon(context),
        color: enabled ? c.foregroundMuted : c.disabledForeground,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        UiInteractive(
          enabled: enabled,
          onTap: enabled ? onTap : null,
          selected: open,
          semanticLabel: item.title,
          builder: (BuildContext ctx, UiInteractiveState s) => AnimatedContainer(
            duration: theme.motion.fast,
            decoration: BoxDecoration(
              color: !enabled
                  ? c.disabledBackground
                  : s.hovered
                      ? c.surfaceHover
                      : (open && variant != UiAccordionVariant.ghost
                          ? c.surfaceMuted
                          : const Color(0x00000000)),
              border: accent != null
                  ? Border(left: BorderSide(color: accent, width: ctx.sz(3)))
                  : null,
            ),
            foregroundDecoration: s.focused
                ? uiFocusRing(ctx, BorderRadius.zero)
                : null,
            padding: pad,
            child: Row(
              children: <Widget>[
                if (chevronLeading) ...<Widget>[
                  chevron,
                  SizedBox(width: ctx.sp(theme.spacing.sm)),
                ],
                if (item.leading != null) ...<Widget>[
                  item.leading!,
                  SizedBox(width: ctx.sp(theme.spacing.md)),
                ] else if (item.leadingIcon != null) ...<Widget>[
                  Icon(
                    item.leadingIcon,
                    size: size.icon(ctx),
                    color: accent ??
                        (enabled ? c.foregroundMuted : c.disabledForeground),
                  ),
                  SizedBox(width: ctx.sp(theme.spacing.md)),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.title,
                        style: size.textStyle(ctx).copyWith(
                              color: enabled
                                  ? (accent ?? c.foreground)
                                  : c.disabledForeground,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      if (item.subtitle != null)
                        Text(
                          item.subtitle!,
                          style: ctx.uiText.caption
                              .copyWith(color: c.foregroundMuted),
                        ),
                    ],
                  ),
                ),
                if (item.badge != null) ...<Widget>[
                  SizedBox(width: ctx.sp(theme.spacing.sm)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ctx.sp(theme.spacing.xs),
                    ),
                    decoration: BoxDecoration(
                      color: (accent ?? c.foregroundMuted)
                          .withValues(alpha: 0.14),
                      borderRadius: ctx.radius(theme.radii.pill),
                    ),
                    child: Text(
                      item.badge!,
                      style: ctx.uiText.caption
                          .copyWith(color: accent ?? c.foregroundMuted),
                    ),
                  ),
                ],
                if (item.trailing != null) ...<Widget>[
                  SizedBox(width: ctx.sp(theme.spacing.sm)),
                  item.trailing!,
                ],
                if (!chevronLeading) ...<Widget>[
                  SizedBox(width: ctx.sp(theme.spacing.sm)),
                  chevron,
                ],
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: theme.motion.normal,
          sizeCurve: theme.motion.curve,
          firstCurve: theme.motion.curve,
          crossFadeState:
              open ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Container(
            width: double.infinity,
            padding: pad.copyWith(top: 0),
            child: DefaultTextStyle(
              style: context.uiText.body.copyWith(color: c.foregroundMuted),
              child: item.content,
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
        if (showDivider)
          Container(height: theme.borders.hairline, color: c.border),
      ],
    );
  }
}
