import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

class AllOptionsScreen extends StatelessWidget {
  const AllOptionsScreen({super.key});

  static const _options = [
    _OptionItem(
      title: 'Habits',
      subtitle: 'Track daily habits & streaks',
      icon: Icons.repeat_rounded,
      route: '/habits',
    ),
    _OptionItem(
      title: 'Routines',
      subtitle: 'Build daily time blocks',
      icon: Icons.alt_route_rounded,
      route: '/routines',
    ),
    _OptionItem(
      title: 'Calendar',
      subtitle: 'Schedule tasks & events',
      icon: Icons.calendar_month_rounded,
      route: '/calendar',
    ),
    _OptionItem(
      title: 'Goals',
      subtitle: 'Set milestones & targets',
      icon: Icons.flag_rounded,
      route: '/goals',
    ),
    _OptionItem(
      title: 'Journal',
      subtitle: 'Reflect & express ideas',
      icon: Icons.menu_book_rounded,
      route: '/journal',
    ),
    _OptionItem(
      title: 'Courses',
      subtitle: 'Track grades & assignments',
      icon: Icons.school_rounded,
      route: '/courses',
    ),
    _OptionItem(
      title: 'Analytics',
      subtitle: 'Productivity trends',
      icon: Icons.insights_rounded,
      route: '/analytics',
    ),
    _OptionItem(
      title: 'Clock & Focus',
      subtitle: 'Time deep work sessions',
      icon: Icons.access_time_rounded,
      route: '/clock',
    ),
    _OptionItem(
      title: 'AI Capture',
      subtitle: 'Smart voice & text AI',
      icon: Icons.auto_awesome_rounded,
      route: '/ai',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = context.ui;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return UiPage(
      header: const UiHeader(
        title: 'All Options',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Minimal drawer grid of all QuietNote modules.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.92,
            ),
            itemCount: _options.length,
            itemBuilder: (context, index) {
              final opt = _options[index];
              return UiInteractive(
                onTap: () => context.push(opt.route),
                builder: (context, state) {
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 12,
                          spreadRadius: 0,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 12,
                      ),
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
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: theme.colors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  opt.icon,
                                  size: 20,
                                  color: theme.colors.primary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                opt.title,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.uiText.caption.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colors.foreground,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                opt.subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: context.uiText.caption.copyWith(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w400,
                                  color: theme.colors.foregroundMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OptionItem {
  const _OptionItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.route,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String route;
}
