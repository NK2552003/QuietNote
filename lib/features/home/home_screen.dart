import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/features/ai/local_ai_engine.dart';

/// Which calendar day the Today view is currently showing.
/// Defaults to today; the date strip lets the person look at any day
/// in the current week without leaving Home.
final selectedDayProvider = StateProvider<DateTime>(
  (ref) => _dateOnly(DateTime.now()),
);

/// Session-only "done today" state for habits and routines.
///
/// The current schema doesn't persist a per-day completion log for habits
/// or routines (only a running `streak` counter), so this keeps the check
/// mark reflected in the UI for the session. Tasks are real, persisted
/// completions via [TaskRepository.toggleTaskCompletion].
final _sessionDoneProvider = StateProvider<Set<String>>((ref) => <String>{});

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

enum _TodayKind { task, habit, routine, event }

class _TodayItem {
  _TodayItem({
    required this.kind,
    required this.id,
    required this.title,
    this.subtitle,
    this.timeLabel,
    required this.done,
    required this.onToggle,
    this.color,
  });

  final _TodayKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? timeLabel;
  final bool done;
  final VoidCallback onToggle;
  final Color? color;
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Good night';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aiState = ref.watch(aiEngineProvider);
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final selectedDay = ref.watch(selectedDayProvider);
    final sessionDone = ref.watch(_sessionDoneProvider);

    final tasksAsync = ref.watch(tasksStreamProvider);
    final habitsAsync = ref.watch(habitsStreamProvider);
    final routinesAsync = ref.watch(routinesStreamProvider);
    final eventsAsync = ref.watch(aggregatedCalendarEventsProvider);

    final bool isLoading =
        tasksAsync.isLoading ||
        habitsAsync.isLoading ||
        routinesAsync.isLoading ||
        eventsAsync.isLoading;

    final Object? firstError =
        tasksAsync.error ??
        habitsAsync.error ??
        routinesAsync.error ??
        eventsAsync.error;

    return UiPage(
      header: UiHeader(
        title: settings.displayName.trim().isEmpty
            ? _greeting()
            : '${_greeting()}, ${settings.displayName.trim()}',
        subtitle: DateFormat('EEEE, MMMM d').format(selectedDay),
        actions: [
          UiIconButton(
            icon: Icons.auto_awesome,
            tooltip: 'Ask AI',
            onPressed: () => context.go('/ai'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DateStrip(
            selected: selectedDay,
            onSelect: (d) => ref.read(selectedDayProvider.notifier).state = d,
          ),
          const SizedBox(height: 24),
          if (aiState == AiEngineState.missingModel) ...[
            UiCard(
              onTap: () => context.go('/settings'),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: context.uiColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline AI not configured',
                          style: context.uiText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to download & set up the local model.',
                          style: context.uiText.caption,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: context.uiColors.foregroundMuted,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (firstError != null)
            UiCard(
              accentColor: context.uiColors.destructive,
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    color: context.uiColors.destructive,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Some data could not load: $firstError',
                      style: context.uiText.caption.copyWith(
                        color: context.uiColors.destructive,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (isLoading)
            const _TodaySkeleton()
          else
            _TodayBody(
              selectedDay: selectedDay,
              tasks: tasksAsync.value ?? const [],
              habits: habitsAsync.value ?? const [],
              routines: routinesAsync.value ?? const [],
              events: eventsAsync.value ?? const [],
              sessionDone: sessionDone,
              ref: ref,
            ),
        ],
      ),
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({
    required this.selectedDay,
    required this.tasks,
    required this.habits,
    required this.routines,
    required this.events,
    required this.sessionDone,
    required this.ref,
  });

  final DateTime selectedDay;
  final List<Task> tasks;
  final List<Habit> habits;
  final List<Routine> routines;
  final List<CalendarEvent> events;
  final Set<String> sessionDone;
  final WidgetRef ref;

  bool get _isToday => _dateOnly(DateTime.now()) == selectedDay;

  @override
  Widget build(BuildContext context) {
    final items = <_TodayItem>[];

    // Calendar events scheduled for the selected day.
    for (final e in events) {
      final start = _dateOnly(e.startTime);
      if (start != selectedDay) continue;
      items.add(
        _TodayItem(
          kind: _TodayKind.event,
          id: e.id,
          title: e.title,
          subtitle: e.description,
          timeLabel: e.isAllDay
              ? 'All day'
              : DateFormat.jm().format(e.startTime),
          done: false,
          onToggle: () {},
          color: e.color != null ? Color(e.color!) : null,
        ),
      );
    }

    // Tasks: due on the selected day, or undated tasks (only surfaced on
    // today, so they don't pile up on every day of the week).
    for (final t in tasks) {
      final due = t.dueDate == null ? null : _dateOnly(t.dueDate!);
      final belongsHere = due == selectedDay || (due == null && _isToday);
      if (!belongsHere) continue;
      items.add(
        _TodayItem(
          kind: _TodayKind.task,
          id: t.id,
          title: t.title,
          subtitle: t.subtitle.isEmpty ? null : t.subtitle,
          timeLabel: due != null ? DateFormat.jm().format(t.dueDate!) : null,
          done: t.isCompleted,
          onToggle: () => ref
              .read(taskRepositoryProvider)
              .toggleTaskCompletion(t.id, t.isCompleted),
        ),
      );
    }

    // Habits are recurring, so they show up every day.
    for (final h in habits) {
      final key = 'habit:${h.id}:${selectedDay.toIso8601String()}';
      final done = sessionDone.contains(key);
      items.add(
        _TodayItem(
          kind: _TodayKind.habit,
          id: h.id,
          title: h.title,
          subtitle: h.streak > 0 ? '${h.streak} day streak' : 'Start today',
          done: done,
          onToggle: () {
            final notifier = ref.read(_sessionDoneProvider.notifier);
            final next = {...notifier.state};
            if (done) {
              next.remove(key);
            } else {
              next.add(key);
              ref
                  .read(habitRepositoryProvider)
                  .incrementStreak(h.id, h.streak, h.progress);
            }
            notifier.state = next;
          },
        ),
      );
    }

    // Active routines, also recurring day-to-day.
    for (final r in routines) {
      if (!r.isActive) continue;
      final key = 'routine:${r.id}:${selectedDay.toIso8601String()}';
      final done = sessionDone.contains(key);
      items.add(
        _TodayItem(
          kind: _TodayKind.routine,
          id: r.id,
          title: r.title,
          subtitle: r.timeOfDay,
          done: done,
          onToggle: () {
            final notifier = ref.read(_sessionDoneProvider.notifier);
            final next = {...notifier.state};
            done ? next.remove(key) : next.add(key);
            notifier.state = next;
          },
        ),
      );
    }

    // Timed items first (events, timed tasks), then untimed items grouped
    // by kind, matching the calm, scannable "agenda" feel of the reference
    // screenshots.
    items.sort((a, b) {
      if (a.timeLabel != null && b.timeLabel == null) return -1;
      if (a.timeLabel == null && b.timeLabel != null) return 1;
      if (a.timeLabel != null && b.timeLabel != null) {
        return a.timeLabel!.compareTo(b.timeLabel!);
      }
      return a.kind.index.compareTo(b.kind.index);
    });

    final total = items.length;
    final done = items.where((i) => i.done).length;

    if (items.isEmpty) {
      return const UiEmptyState(
        title: 'Your day is clear',
        message: 'Nothing scheduled. Take a deep breath, or add something new.',
        icon: Icons.wb_sunny_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        UiCard(
          child: Row(
            children: [
              UiProgressCircle(
                value: total == 0 ? 0 : done / total,
                size: 44,
                thickness: 5,
                center: Text(
                  '$done/$total',
                  style: context.uiText.caption.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today\'s progress', style: context.uiText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? 'Nothing planned'
                          : done == total
                          ? 'All done — nice work'
                          : '${total - done} remaining',
                      style: context.uiText.caption,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _TodayRow(item: item),
          ),
        ),
      ],
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.item});

  final _TodayItem item;

  IconData get _icon => switch (item.kind) {
    _TodayKind.task => Icons.check_circle_outline_rounded,
    _TodayKind.habit => Icons.repeat_rounded,
    _TodayKind.routine => Icons.route_rounded,
    _TodayKind.event => Icons.calendar_month_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final Color tint = item.color ?? c.primary;
    final bool checkable = item.kind != _TodayKind.event;

    return UiCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(_icon, size: 19, color: tint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: context.uiText.bodyStrong.copyWith(
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    color: item.done ? c.foregroundMuted : null,
                  ),
                ),
                if (item.subtitle != null || item.timeLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (item.timeLabel != null) item.timeLabel,
                      if (item.subtitle != null) item.subtitle,
                    ].whereType<String>().join(' · '),
                    style: context.uiText.caption,
                  ),
                ],
              ],
            ),
          ),
          if (checkable)
            GestureDetector(
              onTap: item.onToggle,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: item.done ? tint : c.border,
                    width: 2,
                  ),
                  color: item.done ? tint : Colors.transparent,
                ),
                child: item.done
                    ? Icon(Icons.check, size: 16, color: c.surface)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DateStrip extends StatelessWidget {
  const _DateStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final startOfWeek = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => startOfWeek.add(Duration(days: i)));

    return SizedBox(
      height: 68,
      child: Row(
        children: days.map((d) {
          final isSelected = d == selected;
          final isToday = d == today;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: isSelected
                      ? context.uiColors.primary
                      : context.uiColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? context.uiColors.primary
                        : isToday
                        ? context.uiColors.borderStrong
                        : context.uiColors.border,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      DateFormat.E().format(d).substring(0, 1),
                      style: context.uiText.caption.copyWith(
                        color: isSelected
                            ? context.uiColors.onPrimary.withValues(alpha: 0.7)
                            : context.uiColors.foregroundMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d.day}',
                      style: context.uiText.bodyStrong.copyWith(
                        color: isSelected
                            ? context.uiColors.onPrimary
                            : context.uiColors.foreground,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TodaySkeleton extends StatelessWidget {
  const _TodaySkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 10),
          child: UiCard(
            loading: true,
            loadingHeight: 48,
            child: SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
