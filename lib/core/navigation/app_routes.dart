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
import '../../features/courses/courses_screen.dart';
import '../../features/courses/course_editor_screen.dart';
import '../../features/courses/course_detail_screen.dart';
import '../../features/options/all_options_screen.dart';

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
        GoRoute(
          path: '/',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HomeScreen()),
        ),
        GoRoute(
          path: '/options',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AllOptionsScreen()),
        ),
        GoRoute(
          path: '/habits',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: HabitsScreen()),
        ),
        GoRoute(
          path: '/todos',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: TodosScreen()),
        ),
        GoRoute(
          path: '/notes',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: NotesScreen()),
        ),
        GoRoute(
          path: '/routines',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: RoutinesScreen()),
        ),
        GoRoute(
          path: '/calendar',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CalendarScreen()),
        ),
        GoRoute(
          path: '/goals',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: GoalsScreen()),
        ),
        GoRoute(
          path: '/journal',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: JournalScreen()),
        ),
        GoRoute(
          path: '/analytics',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AnalyticsScreen()),
        ),
        GoRoute(
          path: '/ai',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: AiScreen()),
        ),
        GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: SettingsScreen()),
        ),
        GoRoute(
          path: '/clock',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: ClockScreen()),
        ),
        GoRoute(
          path: '/courses',
          pageBuilder: (context, state) =>
              const NoTransitionPage(child: CoursesScreen()),
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
    GoRoute(
      path: '/courses/new',
      builder: (context, state) => const CourseEditorScreen(),
    ),
    GoRoute(
      path: '/courses/edit/:id',
      builder: (context, state) =>
          CourseEditorScreen(courseId: state.pathParameters['id']),
    ),
    GoRoute(
      path: '/courses/:id',
      builder: (context, state) =>
          CourseDetailScreen(courseId: state.pathParameters['id']!),
    ),
  ],
);

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late final PageController _pageController;
  int _currentIndex = 0;
  final Set<int> _visitedIndices = <int>{0};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  void _markVisited(int index) {
    if (!_visitedIndices.contains(index)) {
      _visitedIndices.add(index);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  static int _calculateSelectedIndex(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    if (location.startsWith('/todos')) return 1;
    if (location.startsWith('/notes')) return 2;
    if (location.startsWith('/settings')) return 3;
    if (location.startsWith('/options') ||
        location.startsWith('/habits') ||
        location.startsWith('/routines') ||
        location.startsWith('/calendar') ||
        location.startsWith('/goals') ||
        location.startsWith('/journal') ||
        location.startsWith('/courses') ||
        location.startsWith('/analytics') ||
        location.startsWith('/clock') ||
        location.startsWith('/ai')) {
      return 4;
    }
    return 0;
  }

  static String _routeForIndex(int index) {
    switch (index) {
      case 0:
        return '/';
      case 1:
        return '/todos';
      case 2:
        return '/notes';
      case 3:
        return '/settings';
      case 4:
        return '/options';
      default:
        return '/';
    }
  }

  void _onItemTapped(int index) {
    _markVisited(index);
    final String targetRoute = _routeForIndex(index);
    final String currentRoute = GoRouterState.of(context).uri.path;

    if (currentRoute != targetRoute) {
      final int prevIndex = _currentIndex;
      setState(() {
        _currentIndex = index;
      });
      if (_pageController.hasClients) {
        if ((index - prevIndex).abs() > 1) {
          _pageController.jumpToPage(index);
        } else {
          _pageController.animateToPage(
            index,
            duration: const Duration(milliseconds: 120),
            curve: Curves.fastOutSlowIn,
          );
        }
      }
      context.go(targetRoute);
    } else if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
    }
  }

  Widget _buildPage(int index) {
    if (!_visitedIndices.contains(index)) {
      return const SizedBox.shrink();
    }
    final Widget content = switch (index) {
      0 => const HomeScreen(),
      1 => const TodosScreen(),
      2 => const NotesScreen(),
      3 => const SettingsScreen(),
      4 => const AllOptionsScreen(),
      _ => const SizedBox.shrink(),
    };
    return RepaintBoundary(child: _KeepAliveWrapper(child: content));
  }

  @override
  Widget build(BuildContext context) {
    final String location = GoRouterState.of(context).uri.path;
    final bool isMainTabRoute = location == '/' ||
        location.startsWith('/todos') ||
        location.startsWith('/notes') ||
        location.startsWith('/settings') ||
        location.startsWith('/options');

    final int calculatedIndex = _calculateSelectedIndex(context);

    if (isMainTabRoute && _currentIndex != calculatedIndex) {
      _currentIndex = calculatedIndex;
      _markVisited(calculatedIndex);
      if (_pageController.hasClients &&
          _pageController.page?.round() != calculatedIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_pageController.hasClients) {
            _pageController.jumpToPage(calculatedIndex);
          }
        });
      }
    }

    final selectedIndex =
        isMainTabRoute ? _currentIndex : calculatedIndex;

    return UiNavShell(
      selectedIndex: selectedIndex,
      onChanged: (idx) => _onItemTapped(idx),
      items: const [
        UiTabItem(icon: Icons.home_outlined, label: 'Home'),
        UiTabItem(icon: Icons.checklist_outlined, label: 'Todos'),
        UiTabItem(icon: Icons.notes_outlined, label: 'Notes'),
        UiTabItem(icon: Icons.settings_outlined, label: 'Settings'),
        UiTabItem(icon: Icons.grid_view_outlined, label: 'Options'),
      ],
      body: isMainTabRoute
          ? PageView.builder(
              controller: _pageController,
              physics: const ClampingScrollPhysics(),
              allowImplicitScrolling: false,
              itemCount: 5,
              onPageChanged: (index) {
                _markVisited(index);
                if (_currentIndex != index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  context.go(_routeForIndex(index));
                }
              },
              itemBuilder: (context, index) => _buildPage(index),
            )
          : widget.child,
    );
  }
}

class _KeepAliveWrapper extends StatefulWidget {
  const _KeepAliveWrapper({required this.child});
  final Widget child;

  @override
  State<_KeepAliveWrapper> createState() => _KeepAliveWrapperState();
}

class _KeepAliveWrapperState extends State<_KeepAliveWrapper>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
