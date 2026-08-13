import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

import '../../features/home/home_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/habits/habit_editor_screen.dart';
import '../../features/habits/habit_detail_screen.dart';
import '../../features/todos/todos_screen.dart';
import '../../features/todos/todo_editor_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/notes/note_editor_screen.dart';
import '../../features/notes/note_preview_screen.dart';
import '../../features/routines/routines_screen.dart';
import '../../features/routines/routine_editor_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/calendar/calendar_event_editor_screen.dart';
import '../../features/calendar/calendar_event_preview_screen.dart';
import '../../features/goals/goals_screen.dart';
import '../../features/goals/goal_editor_screen.dart';
import '../../features/journal/journal_screen.dart';
import '../../features/journal/journal_editor_screen.dart';
import '../../features/journal/journal_preview_screen.dart';
import '../../features/analytics/analytics_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/settings_appearance_screen.dart';
import '../../features/settings/settings_notifications_screen.dart';
import '../../features/settings/settings_ai_screen.dart';
import '../../features/settings/settings_data_screen.dart';
import '../../features/settings/settings_about_screen.dart';
import '../../features/settings/profile_screen.dart';
import '../../features/ai/ai_screen.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/clock/clock_screen.dart';
import '../../features/search/global_search_screen.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();
final shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    // Splash + onboarding live outside the nav shell so the tab bar never
    // shows during first run.
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    ShellRoute(
      navigatorKey: shellNavigatorKey,
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/habits',
          builder: (context, state) => const HabitsScreen(),
        ),
        GoRoute(
          path: '/todos',
          builder: (context, state) => const TodosScreen(),
        ),
        GoRoute(
          path: '/notes',
          builder: (context, state) => const NotesScreen(),
        ),
        GoRoute(
          path: '/routines',
          builder: (context, state) => const RoutinesScreen(),
        ),
        GoRoute(
          path: '/calendar',
          builder: (context, state) => const CalendarScreen(),
        ),
        GoRoute(
          path: '/goals',
          builder: (context, state) => const GoalsScreen(),
        ),
        GoRoute(
          path: '/journal',
          builder: (context, state) => const JournalScreen(),
        ),
        GoRoute(
          path: '/analytics',
          builder: (context, state) => const AnalyticsScreen(),
        ),
        GoRoute(path: '/ai', builder: (context, state) => const AiScreen()),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: '/clock',
          builder: (context, state) => const ClockScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/settings/appearance',
      builder: (context, state) => const SettingsAppearanceScreen(),
    ),
    GoRoute(
      path: '/settings/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/settings/notifications',
      builder: (context, state) => const SettingsNotificationsScreen(),
    ),
    GoRoute(
      path: '/settings/ai',
      builder: (context, state) => const SettingsAiScreen(),
    ),
    GoRoute(
      path: '/settings/data',
      builder: (context, state) => const SettingsDataScreen(),
    ),
    GoRoute(
      path: '/settings/about',
      builder: (context, state) => const SettingsAboutScreen(),
    ),
    GoRoute(
      path: '/habits/new',
      builder: (context, state) => const HabitEditorScreen(),
    ),
    GoRoute(
      path: '/habits/edit/:id',
      builder: (context, state) =>
          HabitEditorScreen(habitId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/habits/:id',
      builder: (context, state) =>
          HabitDetailScreen(habitId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/notes/new',
      builder: (context, state) => const NoteEditorScreen(),
    ),
    GoRoute(
      path: '/notes/edit/:id',
      builder: (context, state) =>
          NoteEditorScreen(noteId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/notes/:id',
      builder: (context, state) =>
          NotePreviewScreen(noteId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/todos/new',
      builder: (context, state) => const TodoEditorScreen(),
    ),
    GoRoute(
      path: '/todos/edit/:id',
      builder: (context, state) =>
          TodoEditorScreen(taskId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/calendar/new',
      builder: (context, state) {
        final dateParam = state.uri.queryParameters['date'];
        return CalendarEventEditorScreen(
          initialDate: dateParam == null ? null : DateTime.tryParse(dateParam),
        );
      },
    ),
    GoRoute(
      path: '/calendar/edit/:id',
      builder: (context, state) =>
          CalendarEventEditorScreen(eventId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/calendar/:id',
      builder: (context, state) =>
          CalendarEventPreviewScreen(eventId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/goals/new',
      builder: (context, state) => const GoalEditorScreen(),
    ),
    GoRoute(
      path: '/goals/edit/:id',
      builder: (context, state) =>
          GoalEditorScreen(goalId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/routines/new',
      builder: (context, state) => const RoutineEditorScreen(),
    ),
    GoRoute(
      path: '/routines/edit/:id',
      builder: (context, state) =>
          RoutineEditorScreen(routineId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/journal/new',
      builder: (context, state) => const JournalEditorScreen(),
    ),
    GoRoute(
      path: '/journal/edit/:id',
      builder: (context, state) =>
          JournalEditorScreen(entryId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/journal/:id',
      builder: (context, state) =>
          JournalPreviewScreen(entryId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/search',
      builder: (context, state) => const GlobalSearchScreen(),
    ),
  ],
);

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return UiNavShell(
      selectedIndex: _calculateSelectedIndex(context),
      onChanged: (idx) => _onItemTapped(idx, context),
      items: const [
        UiTabItem(icon: Icons.home_outlined, label: 'Home'),
        UiTabItem(icon: Icons.repeat_outlined, label: 'Habits'),
        UiTabItem(icon: Icons.checklist_outlined, label: 'Todos'),
        UiTabItem(icon: Icons.notes_outlined, label: 'Notes'),
        UiTabItem(icon: Icons.route_outlined, label: 'Routines'),
        UiTabItem(icon: Icons.calendar_month_outlined, label: 'Calendar'),
        UiTabItem(icon: Icons.flag_outlined, label: 'Goals'),
        UiTabItem(icon: Icons.menu_book_outlined, label: 'Journal'),
        UiTabItem(icon: Icons.insights_outlined, label: 'Analytics'),
        UiTabItem(icon: Icons.auto_awesome, label: 'AI Capture'),
        UiTabItem(icon: Icons.settings_outlined, label: 'Settings'),
        UiTabItem(icon: Icons.access_time_outlined, label: 'Clock'),
      ],
      body: child,
    );
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/habits')) return 1;
    if (location.startsWith('/todos')) return 2;
    if (location.startsWith('/notes')) return 3;
    if (location.startsWith('/routines')) return 4;
    if (location.startsWith('/calendar')) return 5;
    if (location.startsWith('/goals')) return 6;
    if (location.startsWith('/journal')) return 7;
    if (location.startsWith('/analytics')) return 8;
    if (location.startsWith('/ai')) return 9;
    if (location.startsWith('/settings')) return 10;
    if (location.startsWith('/clock')) return 11;
    return 0;
  }

  void _onItemTapped(int index, BuildContext context) {
    switch (index) {
      case 0:
        context.go('/');
        break;
      case 1:
        context.go('/habits');
        break;
      case 2:
        context.go('/todos');
        break;
      case 3:
        context.go('/notes');
        break;
      case 4:
        context.go('/routines');
        break;
      case 5:
        context.go('/calendar');
        break;
      case 6:
        context.go('/goals');
        break;
      case 7:
        context.go('/journal');
        break;
      case 8:
        context.go('/analytics');
        break;
      case 9:
        context.go('/ai');
        break;
      case 10:
        context.go('/settings');
        break;
      case 11:
        context.go('/clock');
        break;
    }
  }
}
