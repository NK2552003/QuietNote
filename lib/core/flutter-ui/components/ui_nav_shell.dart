import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/focus_preset.dart';
import 'package:quietnote/features/clock/zen_focus_screen.dart';

import '../theme/ui_theme.dart';
import 'ui_common.dart';
import 'ui_tabs.dart';

/// Bottom navigation for the mobile app shell, side rail on wide screens.
class UiNavShell extends StatefulWidget {
  const UiNavShell({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onChanged,
    required this.body,
    this.floatingAction,
  });

  final List<UiTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final Widget body;
  final Widget? floatingAction;

  @override
  State<UiNavShell> createState() => _UiNavShellState();
}

class _UiNavShellState extends State<UiNavShell> {
  bool _isMenuOpen = false;

  void _toggleQuickMenu() {
    HapticFeedback.selectionClick();
    setState(() {
      _isMenuOpen = !_isMenuOpen;
    });
  }

  void _closeQuickMenu() {
    if (_isMenuOpen) {
      setState(() {
        _isMenuOpen = false;
      });
    }
  }

  IconData _getActiveIcon(IconData? icon) {
    if (icon == Icons.home_outlined) return Icons.home_rounded;
    if (icon == Icons.repeat_outlined) return Icons.repeat_rounded;
    if (icon == Icons.checklist_outlined) return Icons.task_alt_rounded;
    if (icon == Icons.notes_outlined) return Icons.sticky_note_2_rounded;
    if (icon == Icons.route_outlined) return Icons.alt_route_rounded;
    if (icon == Icons.calendar_month_outlined) {
      return Icons.calendar_month_rounded;
    }
    if (icon == Icons.flag_outlined) return Icons.flag_rounded;
    if (icon == Icons.menu_book_outlined) return Icons.menu_book_rounded;
    if (icon == Icons.school_outlined) return Icons.school_rounded;
    if (icon == Icons.insights_outlined) return Icons.insights_rounded;
    if (icon == Icons.auto_awesome_outlined) return Icons.auto_awesome;
    if (icon == Icons.auto_awesome) return Icons.auto_awesome;
    if (icon == Icons.settings_outlined) return Icons.settings_rounded;
    if (icon == Icons.access_time_outlined) return Icons.access_time_rounded;
    return icon ?? Icons.circle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool rail = !context.uiRes.isMobile;

    if (rail) {
      return Scaffold(
        backgroundColor: theme.colors.background,
        body: Row(
          children: <Widget>[
            Container(
              width: context.sz(context.uiRes.isDesktop ? 210 : 72),
              decoration: BoxDecoration(
                color: theme.colors.surface,
                border: Border(
                  right: BorderSide(
                    color: theme.colors.border,
                    width: theme.borders.hairline,
                  ),
                ),
              ),
              child: SafeArea(
                child: Column(
                  children: <Widget>[
                    SizedBox(height: context.sp(theme.spacing.lg)),
                    for (int i = 0; i < widget.items.length; i++)
                      _UiNavEntry(
                        item: widget.items[i],
                        activeIcon: _getActiveIcon(widget.items[i].icon),
                        selected: i == widget.selectedIndex,
                        showLabel: context.uiRes.isDesktop,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onChanged(i);
                        },
                      ),
                    const Spacer(),
                    Consumer(
                      builder: (context, ref, _) {
                        final settings = ref.watch(settingsProvider).value;
                        final focusEnd = settings?.focusSessionEndsAt;
                        if (focusEnd == null || !focusEnd.isAfter(DateTime.now())) {
                          return const SizedBox.shrink();
                        }
                        final activeSession =
                            ref.watch(activeFocusSessionProvider).value;
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: context.uiRes.isDesktop ? 10 : 4,
                            vertical: 6,
                          ),
                          child: _NavFocusBubble(
                            end: focusEnd,
                            phase: settings?.focusSessionPhase ?? 'work',
                            isDesktop: context.uiRes.isDesktop,
                            presetLabel:
                                focusPresetFromId(activeSession?.presetId)
                                    ?.chipLabel,
                            onTap: () => ZenFocusScreen.open(
                              context,
                              ref,
                              end: focusEnd,
                              startedAt: settings?.focusSessionStartedAt ?? activeSession?.startedAt,
                              phase: settings?.focusSessionPhase,
                            ),
                          ),
                        );
                      },
                    ),
                    if (widget.floatingAction != null)
                      Padding(
                        padding: EdgeInsets.all(context.sp(theme.spacing.lg)),
                        child: widget.floatingAction!,
                      ),
                  ],
                ),
              ),
            ),
            Expanded(child: widget.body),
          ],
        ),
      );
    }

    // Mobile layout (fixed 5-slot dock): Home (0), Todos (2), + (Middle
    // quick-grid trigger), Notes (3), Settings (10). Every other
    // destination lives behind the '+' as a 3x3 grid of tiles.
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    // Calculate active dock slot (0 to 4). Slot 2 is the '+' trigger (Options page 4);
    // it lights up whenever the currently selected screen is 4 or an option.
    int activeNavIndex = 2;
    if (!_isMenuOpen) {
      if (widget.selectedIndex == 0) {
        activeNavIndex = 0; // Home
      } else if (widget.selectedIndex == 1) {
        activeNavIndex = 1; // Todos
      } else if (widget.selectedIndex == 2) {
        activeNavIndex = 3; // Notes
      } else if (widget.selectedIndex == 3) {
        activeNavIndex = 4; // Settings
      } else if (widget.selectedIndex == 4) {
        activeNavIndex = 2; // All Options Grid (Middle slot)
      }
    }

    const gridOptions = [
      _QuickGridItem(
        icon: Icons.repeat_rounded,
        label: 'Habits',
        route: '/habits',
      ),
      _QuickGridItem(
        icon: Icons.alt_route_rounded,
        label: 'Routines',
        route: '/routines',
      ),
      _QuickGridItem(
        icon: Icons.calendar_month_rounded,
        label: 'Calendar',
        route: '/calendar',
      ),
      _QuickGridItem(icon: Icons.flag_rounded, label: 'Goals', route: '/goals'),
      _QuickGridItem(
        icon: Icons.menu_book_rounded,
        label: 'Journal',
        route: '/journal',
      ),
      _QuickGridItem(
        icon: Icons.school_rounded,
        label: 'Courses',
        route: '/courses',
      ),
      _QuickGridItem(
        icon: Icons.insights_rounded,
        label: 'Analytics',
        route: '/analytics',
      ),
      _QuickGridItem(
        icon: Icons.access_time_rounded,
        label: 'Clock',
        route: '/clock',
      ),
      _QuickGridItem(
        icon: Icons.auto_awesome,
        label: 'AI Capture',
        route: '/ai',
      ),
    ];
    assert(gridOptions.length == 9, 'Quick-grid must hold exactly 9 tiles');

    return Scaffold(
      extendBody:
          true, // Allows body to extend behind the floating glass tab bar
      backgroundColor: theme.colors.background,
      body: Stack(
        children: [
          Positioned.fill(child: widget.body),

          // Tap Outside Backdrop Overlay
          if (_isMenuOpen) ...[
            Positioned.fill(
              child: GestureDetector(
                onTap: _closeQuickMenu,
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.black.withValues(alpha: 0.55)),
              ),
            ),

            // Floating Option Bubble Cards Pop Up from Bottom Nav Bar
            Positioned(
              left: 16,
              right: 16,
              bottom: 84 + MediaQuery.of(context).padding.bottom,
              child: TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutBack,
                tween: Tween<double>(begin: 0.0, end: 1.0),
                builder: (context, val, child) {
                  return Transform.scale(
                    scale: 0.5 + (0.5 * val),
                    alignment: Alignment.bottomCenter,
                    child: Opacity(
                      opacity: val.clamp(0.0, 1.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int row = 0; row < 3; row++) ...[
                            if (row != 0) const SizedBox(height: 8),
                            Row(
                              children: [
                                for (int col = 0; col < 3; col++) ...[
                                  if (col != 0) const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildBubbleCard(
                                      gridOptions[row * 3 + col],
                                      isDark,
                                      theme,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          // Interactive Floating Focus Pill (When timer active and user is outside /clock)
          Positioned(
            left: 0,
            right: 0,
            bottom: 78 + MediaQuery.of(context).padding.bottom,
            child: Consumer(
              builder: (context, ref, _) {
                final settings = ref.watch(settingsProvider).value;
                final focusEnd = settings?.focusSessionEndsAt;
                if (focusEnd == null ||
                    !focusEnd.isAfter(DateTime.now()) ||
                    _isMenuOpen) {
                  return const SizedBox.shrink();
                }
                final location = GoRouterState.of(context).uri.path;
                if (location == '/' || location == '/clock' || location.isEmpty) {
                  return const SizedBox.shrink();
                }

                final bool hasFloatingButton = location.startsWith('/todos') ||
                    location.startsWith('/notes') ||
                    location.startsWith('/habits') ||
                    location.startsWith('/routines') ||
                    location.startsWith('/calendar') ||
                    location.startsWith('/goals') ||
                    location.startsWith('/journal') ||
                    location.startsWith('/courses') ||
                    location.startsWith('/flashcards') ||
                    location.startsWith('/note') ||
                    location.startsWith('/journal_preview');

                final activeSession =
                    ref.watch(activeFocusSessionProvider).value;
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(
                    left: 16,
                    right: hasFloatingButton ? 80 : 16,
                  ),
                  child: _MobileFloatingFocusPill(
                    end: focusEnd,
                    startedAt: settings?.focusSessionStartedAt ?? activeSession?.startedAt,
                    phase: settings?.focusSessionPhase ?? 'work',
                    hasFloatingButton: hasFloatingButton,
                    presetLabel:
                        focusPresetFromId(activeSession?.presetId)?.chipLabel,
                    onTap: () {
                      _closeQuickMenu();
                      ZenFocusScreen.open(
                        context,
                        ref,
                        end: focusEnd,
                        startedAt: settings?.focusSessionStartedAt ?? activeSession?.startedAt,
                        phase: settings?.focusSessionPhase,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            margin: EdgeInsets.only(
              bottom: (context.sp(theme.spacing.md) - 2).clamp(0.0, 48.0),
            ),
            width: 280,
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 18,
                  spreadRadius: 0,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xDC1A1817)
                      : theme.colors.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1.2,
                  ),
                ),
                child: Stack(
                  children: [
                    // Sliding Bubble Shift Background Animation
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.fastOutSlowIn,
                      alignment: Alignment(-1.0 + (activeNavIndex * 0.5), 0.0),
                      child: FractionallySizedBox(
                        widthFactor: 0.20,
                        heightFactor: 1.0,
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.14)
                                  : theme.colors.primary.withValues(
                                      alpha: 0.10,
                                    ),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.22)
                                    : theme.colors.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // Foreground Interactive Tabs: Home (0), Todos (1), Options (4), Notes (2), Settings (3)
                    Row(
                      children: <Widget>[
                        // Home (0)
                        Expanded(
                          child: _UiNavEntry(
                            item: widget.items[0],
                            activeIcon: _getActiveIcon(widget.items[0].icon),
                            selected: !_isMenuOpen && widget.selectedIndex == 0,
                            showLabel: false,
                            vertical: true,
                            isBubbleTab: true,
                            onTap: () {
                              _closeQuickMenu();
                              widget.onChanged(0);
                            },
                          ),
                        ),
                        // Todos (1)
                        Expanded(
                          child: _UiNavEntry(
                            item: widget.items[1],
                            activeIcon: _getActiveIcon(widget.items[1].icon),
                            selected: !_isMenuOpen && widget.selectedIndex == 1,
                            showLabel: false,
                            vertical: true,
                            isBubbleTab: true,
                            onTap: () {
                              _closeQuickMenu();
                              widget.onChanged(1);
                            },
                          ),
                        ),
                        // Middle Quick Options Drawer Trigger
                        Expanded(
                          child: UiInteractive(
                            onTap: _toggleQuickMenu,
                            semanticLabel: 'Quick Options',
                            builder: (context, state) {
                              final Color activeFg = isDark
                                  ? Colors.white
                                  : theme.colors.primary;
                              final Color inactiveFg = isDark
                                  ? Colors.white.withValues(alpha: 0.55)
                                  : theme.colors.foregroundMuted;

                              return Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 220),
                                  switchInCurve: Curves.easeOutBack,
                                  switchOutCurve: Curves.easeIn,
                                  transitionBuilder: (child, animation) =>
                                      ScaleTransition(
                                        scale: animation,
                                        child: FadeTransition(
                                          opacity: animation,
                                          child: child,
                                        ),
                                      ),
                                  child: Icon(
                                    _isMenuOpen
                                        ? Icons.close_rounded
                                        : Icons.grid_view_rounded,
                                    key: ValueKey<bool>(_isMenuOpen),
                                    size: 22,
                                    color: activeNavIndex == 2 || _isMenuOpen
                                        ? activeFg
                                        : inactiveFg,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Notes (2)
                        Expanded(
                          child: _UiNavEntry(
                            item: widget.items[2],
                            activeIcon: _getActiveIcon(widget.items[2].icon),
                            selected: !_isMenuOpen && widget.selectedIndex == 2,
                            showLabel: false,
                            vertical: true,
                            isBubbleTab: true,
                            onTap: () {
                              _closeQuickMenu();
                              widget.onChanged(2);
                            },
                          ),
                        ),
                        // Settings (3)
                        Expanded(
                          child: _UiNavEntry(
                            item: widget.items[3],
                            activeIcon: _getActiveIcon(widget.items[3].icon),
                            selected:
                                !_isMenuOpen && widget.selectedIndex == 3,
                            showLabel: false,
                            vertical: true,
                            isBubbleTab: true,
                            onTap: () {
                              _closeQuickMenu();
                              widget.onChanged(3);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleCard(_QuickGridItem item, bool isDark, UiTheme theme) {
    return UiInteractive(
      onTap: () {
        _closeQuickMenu();
        context.push(item.route);
      },
      builder: (context, state) {
        return Container(
          height: 68,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 18,
                spreadRadius: 0,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isDark
                  ? (state.hovered
                      ? const Color(0xFE252321)
                      : const Color(0xFE1A1817))
                  : (state.hovered
                      ? theme.colors.surface
                      : theme.colors.surfaceMuted),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 1.2,
              ),
            ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: theme.colors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        item.icon,
                        size: 18,
                        color: theme.colors.primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: context.uiText.caption.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: theme.colors.foreground,
                      ),
                    ),
                  ],
                ),
          ),
        );
      },
    );
  }
}

class _QuickGridItem {
  final IconData icon;
  final String label;
  final String route;
  const _QuickGridItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class _UiNavEntry extends StatelessWidget {
  const _UiNavEntry({
    required this.item,
    required this.activeIcon,
    required this.selected,
    required this.showLabel,
    required this.onTap,
    this.vertical = false,
    this.isBubbleTab = false,
  });

  final UiTabItem item;
  final IconData activeIcon;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;
  final bool vertical;
  final bool isBubbleTab;

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    final Color activeFg = isDark ? Colors.white : theme.colors.primary;
    final Color inactiveFg = isDark
        ? Colors.white.withValues(alpha: 0.55)
        : theme.colors.foregroundMuted;

    final IconData displayIcon = selected
        ? activeIcon
        : (item.icon ?? Icons.circle);

    return UiInteractive(
      onTap: onTap,
      semanticLabel: item.label,
      builder: (BuildContext ctx, UiInteractiveState s) {
        return Container(
          decoration: !isBubbleTab
              ? BoxDecoration(
                  color: selected
                      ? (isDark
                            ? theme.colors.primary.withValues(alpha: 0.18)
                            : theme.colors.primary.withValues(alpha: 0.10))
                      : (s.hovered
                            ? theme.colors.surfaceHover.withValues(alpha: 0.5)
                            : Colors.transparent),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: vertical
              ? Center(
                  child: AnimatedScale(
                    scale: selected ? 1.18 : 1.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      displayIcon,
                      size: 22,
                      color: selected ? activeFg : inactiveFg,
                    ),
                  ),
                )
              : Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ctx.sp(theme.spacing.sm),
                    horizontal: ctx.sp(theme.spacing.md),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        displayIcon,
                        size: context.sz(theme.sizes.iconMd),
                        color: selected ? activeFg : inactiveFg,
                      ),
                      if (showLabel) ...<Widget>[
                        SizedBox(width: ctx.sp(theme.spacing.md)),
                        Expanded(
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            style: context.uiText.bodyStrong.copyWith(
                              color: selected ? activeFg : inactiveFg,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive Active Focus Bubble for Sidebar Rail
// ---------------------------------------------------------------------------

class _NavFocusBubble extends StatefulWidget {
  const _NavFocusBubble({
    required this.end,
    this.phase = 'work',
    required this.isDesktop,
    this.presetLabel,
    required this.onTap,
  });

  final DateTime end;
  final String phase;
  final bool isDesktop;
  final String? presetLabel;
  final VoidCallback onTap;

  @override
  State<_NavFocusBubble> createState() => _NavFocusBubbleState();
}

class _NavFocusBubbleState extends State<_NavFocusBubble>
    with SingleTickerProviderStateMixin {
  late Timer _ticker;
  late DateTime _now;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBreak = widget.phase == 'break';
    final Color accentColor =
        isBreak ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);
    final Color ringColor =
        isBreak ? const Color(0xFFFBBF24) : const Color(0xFF818CF8);

    final diff = widget.end.difference(_now).inSeconds.clamp(0, 24 * 60 * 60);
    final min = diff ~/ 60;
    final sec = diff % 60;
    final timeStr =
        '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';

    return GestureDetector(
      onTap: widget.onTap,
      child: Tooltip(
        message: '${isBreak ? "Break" : "Active Focus"} ($timeStr remaining) · Tap to view',
        child: AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (context, _) {
            final pulseVal = _pulseCtrl.value;
            return Container(
              padding: EdgeInsets.symmetric(
                horizontal: widget.isDesktop ? 10 : 8,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12 + 0.08 * pulseVal),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35 + 0.25 * pulseVal),
                  width: 1.2,
                ),
              ),
              child: widget.isDesktop
                  ? Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: accentColor,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor
                                    .withValues(alpha: 0.4 + 0.4 * pulseVal),
                                blurRadius: 6,
                                spreadRadius: 1 + 2 * pulseVal,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isBreak ? 'Break' : (widget.presetLabel ?? 'Focus'),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: ringColor,
                                ),
                              ),
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios_rounded,
                          size: 11,
                          color: ringColor,
                        ),
                      ],
                    )
                  : Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: accentColor,
                              boxShadow: [
                                BoxShadow(
                                  color: accentColor
                                      .withValues(alpha: 0.5),
                                  blurRadius: 4,
                                  spreadRadius: 1 + pulseVal,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile Floating Interactive Focus Pill
// ---------------------------------------------------------------------------

class _MobileFloatingFocusPill extends StatefulWidget {
  const _MobileFloatingFocusPill({
    required this.end,
    this.startedAt,
    this.phase = 'work',
    this.hasFloatingButton = false,
    this.presetLabel,
    required this.onTap,
  });

  final DateTime end;
  final DateTime? startedAt;
  final String phase;
  final bool hasFloatingButton;
  final String? presetLabel;
  final VoidCallback onTap;

  @override
  State<_MobileFloatingFocusPill> createState() =>
      _MobileFloatingFocusPillState();
}

class _MobileFloatingFocusPillState extends State<_MobileFloatingFocusPill>
    with SingleTickerProviderStateMixin {
  late Timer _ticker;
  late DateTime _now;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ticker.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBreak = widget.phase == 'break';
    final Color accentColor =
        isBreak ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);
    final Color ringColor =
        isBreak ? const Color(0xFFFBBF24) : const Color(0xFF818CF8);
    final IconData icon =
        isBreak ? Icons.local_cafe_outlined : Icons.timer_outlined;

    final diff = widget.end.difference(_now).inSeconds.clamp(0, 24 * 60 * 60);
    final min = diff ~/ 60;
    final sec = diff % 60;
    final timeStr =
        '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final effectiveStart =
        widget.startedAt ?? widget.end.subtract(const Duration(minutes: 25));
    final sessionTotalSec = widget.end.difference(effectiveStart).inSeconds;
    final elapsedSec = _now.difference(effectiveStart).inSeconds;
    final progress = sessionTotalSec > 0
        ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final pulseVal = _pulseCtrl.value;
          return Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: isDark
                  ? (isBreak
                      ? const Color(0xE61F1A12)
                      : const Color(0xE6141320))
                  : Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: ringColor.withValues(alpha: 0.35 + 0.3 * pulseVal),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withValues(alpha: 0.12 + 0.08 * pulseVal),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 2.6,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            accentColor.withValues(alpha: 0.18),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            ringColor),
                      ),
                    ),
                    Icon(
                      icon,
                      size: 13,
                      color: ringColor,
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isBreak ? 'Break Time' : (widget.presetLabel ?? 'Focus Active'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ringColor,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isDark ? Colors.white : Colors.black87,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 12,
                  color: ringColor,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
