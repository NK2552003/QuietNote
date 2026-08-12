import 'package:flutter/material.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';

enum UiTabsVariant { underline, pill, segmented, ghost }

typedef UiTabBar = UiTabs;

class UiTabItem {
  const UiTabItem({
    required this.label,
    this.icon,
    this.badge,
    this.count,
    this.intent,
    this.enabled = true,
    this.content,
  });

  final String label;
  final IconData? icon;
  final String? badge;
  final int? count;
  final UiIntent? intent;
  final bool enabled;

  /// Optional panel rendered by [UiTabs] when this tab is active.
  final Widget? content;
}

/// Tab bar (+ optional panel) with four variants, sizes, densities,
/// scrollable/stretch layouts, badges, counts and disabled tabs.
class UiTabs extends StatefulWidget {
  const UiTabs({
    super.key,
    required this.items,
    int? index,
    int? selectedIndex,
    this.initialIndex = 0,
    this.onChanged,
    this.variant = UiTabsVariant.underline,
    this.size = UiSize.md,
    this.density = UiDensity.comfortable,
    this.intent = UiIntent.primary,
    this.stretch = false,
    this.scrollable = false,
    this.trailing,
    this.showPanel = true,
    this.enabled = true,
  }) : index = index ?? selectedIndex;

  final List<UiTabItem> items;

  /// Controlled index; omit for internal state.
  final int? index;
  final int initialIndex;
  final ValueChanged<int>? onChanged;

  final UiTabsVariant variant;
  final UiSize size;
  final UiDensity density;
  final UiIntent intent;

  /// Tabs share the available width equally.
  final bool stretch;
  final bool scrollable;

  /// Widget pinned to the right of the tab row (actions, filters).
  final Widget? trailing;
  final bool showPanel;
  final bool enabled;

  @override
  State<UiTabs> createState() => _UiTabsState();
}

class _UiTabsState extends State<UiTabs> {
  late int _index = widget.initialIndex;

  int get _current => widget.index ?? _index;

  void _select(int i) {
    widget.onChanged?.call(i);
    if (widget.index == null) setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final bool scroll = widget.scrollable || context.uiRes.isMobile;

    final List<Widget> tabs = <Widget>[
      for (int i = 0; i < widget.items.length; i++)
        _UiTab(
          item: widget.items[i],
          selected: i == _current,
          variant: widget.variant,
          size: widget.size,
          density: widget.density,
          intent: widget.items[i].intent ?? widget.intent,
          expand: widget.stretch && !scroll,
          enabled: widget.enabled && widget.items[i].enabled,
          onTap: () => _select(i),
        ),
    ];

    Widget row;
    if (widget.stretch && !scroll) {
      row = Row(
        children: <Widget>[for (final Widget t in tabs) Expanded(child: t)],
      );
    } else if (scroll) {
      row = SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: tabs),
      );
    } else {
      row = Row(mainAxisSize: MainAxisSize.min, children: tabs);
    }

    final double gap = context.sp(theme.spacing.xs);
    Widget bar;
    switch (widget.variant) {
      case UiTabsVariant.underline:
        bar = Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: c.border,
                width: theme.borders.hairline,
              ),
            ),
          ),
          child: row,
        );
        break;
      case UiTabsVariant.segmented:
        bar = Container(
          padding: EdgeInsets.all(gap),
          decoration: BoxDecoration(
            color: c.surfaceMuted,
            borderRadius: context.radius(theme.radii.md),
            border: Border.all(color: c.border, width: theme.borders.hairline),
          ),
          child: row,
        );
        break;
      case UiTabsVariant.pill:
      case UiTabsVariant.ghost:
        bar = row;
        break;
    }

    if (widget.trailing != null) {
      bar = Row(
        children: <Widget>[
          Expanded(child: bar),
          SizedBox(width: context.sp(theme.spacing.md)),
          widget.trailing!,
        ],
      );
    }

    final UiTabItem? active =
        _current >= 0 && _current < widget.items.length
            ? widget.items[_current]
            : null;

    if (!widget.showPanel || active?.content == null) return bar;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        bar,
        SizedBox(height: context.sp(theme.spacing.lg)),
        AnimatedSwitcher(
          duration: theme.motion.normal,
          switchInCurve: theme.motion.curve,
          child: KeyedSubtree(
            key: ValueKey<int>(_current),
            child: active!.content!,
          ),
        ),
      ],
    );
  }
}

class _UiTab extends StatelessWidget {
  const _UiTab({
    required this.item,
    required this.selected,
    required this.variant,
    required this.size,
    required this.density,
    required this.intent,
    required this.expand,
    required this.enabled,
    required this.onTap,
  });

  final UiTabItem item;
  final bool selected;
  final UiTabsVariant variant;
  final UiSize size;
  final UiDensity density;
  final UiIntent intent;
  final bool expand;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final c = theme.colors;
    final Color accent = intent.color(context);
    final double f = density.factor;
    final BorderRadius radius = context.radius(
      variant == UiTabsVariant.pill ? theme.radii.pill : theme.radii.sm,
    );

    return UiInteractive(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      selected: selected,
      semanticLabel: item.label,
      borderRadius: radius,
      builder: (BuildContext ctx, UiInteractiveState s) {
        Color fg;
        if (!enabled) {
          fg = c.disabledForeground;
        } else if (selected) {
          fg = variant == UiTabsVariant.pill ? c.onPrimary : accent;
        } else {
          fg = s.hovered ? c.foreground : c.foregroundMuted;
        }

        Color bg = const Color(0x00000000);
        if (enabled) {
          if (variant == UiTabsVariant.pill && selected) {
            bg = accent;
          } else if (variant == UiTabsVariant.segmented && selected) {
            bg = c.surface;
          } else if (s.hovered && !selected) {
            bg = c.surfaceHover;
          }
        }

        return AnimatedContainer(
          duration: theme.motion.fast,
          curve: theme.motion.curve,
          padding: EdgeInsets.symmetric(
            horizontal: ctx.sp(theme.spacing.md) * f,
            vertical: ctx.sp(theme.spacing.sm) * f,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius:
                variant == UiTabsVariant.underline ? null : radius,
            border: variant == UiTabsVariant.underline
                ? Border(
                    bottom: BorderSide(
                      color: selected ? accent : const Color(0x00000000),
                      width: ctx.sz(2),
                    ),
                  )
                : null,
            boxShadow: variant == UiTabsVariant.segmented && selected
                ? theme.shadows.sm
                : null,
          ),
          foregroundDecoration: s.focused ? uiFocusRing(ctx, radius) : null,
          child: Row(
            mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (item.icon != null) ...<Widget>[
                Icon(item.icon, size: size.icon(ctx), color: fg),
                if (item.label.isNotEmpty) SizedBox(width: ctx.sp(theme.spacing.xs)),
              ],
              if (item.label.isNotEmpty)
                Text(
                  item.label,
                  style: size.textStyle(ctx).copyWith(
                        color: fg,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              if (item.count != null) ...<Widget>[
                SizedBox(width: ctx.sp(theme.spacing.xs)),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ctx.sp(theme.spacing.xs),
                  ),
                  decoration: BoxDecoration(
                    color: selected && variant == UiTabsVariant.pill
                        ? c.onPrimary.withValues(alpha: 0.22)
                        : accent.withValues(alpha: 0.14),
                    borderRadius: ctx.radius(theme.radii.pill),
                  ),
                  child: Text(
                    '${item.count}',
                    style: ctx.uiText.caption.copyWith(color: fg),
                  ),
                ),
              ],
              if (item.badge != null) ...<Widget>[
                SizedBox(width: ctx.sp(theme.spacing.xs)),
                Container(
                  width: ctx.sz(6),
                  height: ctx.sz(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.destructive,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
