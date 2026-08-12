import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/routines/routines_screen.dart';

class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});
  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  late DateTime _now;
  Timer? _ticker;
  int _minutes = 25;
  bool _scheduling = false;
  bool _finishingExpiredSession = false;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final end = ref.read(settingsProvider).value?.focusSessionEndsAt;
      if (end != null && !end.isAfter(_now)) {
        unawaited(_completeExpiredSession());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _startTimer() async {
    if (_scheduling) return;
    setState(() => _scheduling = true);
    final scheduled = DateTime.now().add(Duration(minutes: _minutes));
    // Persist and paint the timer first. Notification permission or platform
    // scheduling must never make the primary Start action feel unresponsive.
    await ref.read(focusSessionRepositoryProvider).start(
          endsAt: scheduled,
          minutes: _minutes,
        );
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));
    if (!mounted) return;
    setState(() => _scheduling = false);
    UiToast.show(context,
      title: 'Focus session started',
      message: 'Ends at ${DateFormat.jm().format(scheduled)}. It is saved to your focus history.',
      intent: UiIntent.success, icon: Icons.timer_outlined);
    // Scheduling is deliberately non-blocking: the running timer remains
    // correct even if a device has notifications disabled.
    unawaited(_scheduleCompletionAlert(scheduled));
    unawaited(NotificationService().showFocusTimerStatus(scheduled));
  }

  Future<void> _scheduleCompletionAlert(DateTime scheduled) async {
    final ok = await NotificationService().scheduleReminder(
      NotificationService.focusStatusNotificationId,
      'Focus timer complete',
      'Your $_minutes-minute focus session is complete.',
      scheduled,
    );
    if (!mounted || ok) return;
    UiToast.show(context,
      title: 'Timer is still running',
      message: 'Enable notifications in Settings to receive its completion alert.',
      intent: UiIntent.warning, icon: Icons.notifications_off_outlined);
  }

  Future<void> _cancelFocus() async {
    await NotificationService().clearFocusTimerStatus();
    await ref.read(focusSessionRepositoryProvider).finishActive(cancelled: true);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(clearFocusSession: true));
  }

  Future<void> _completeExpiredSession() async {
    if (_finishingExpiredSession) return;
    _finishingExpiredSession = true;
    await ref.read(focusSessionRepositoryProvider).finishActive();
    await NotificationService().clearFocusTimerStatus();
    await ref.read(settingsProvider.notifier).update(
          (s) => s.copyWith(clearFocusSession: true),
        );
    _finishingExpiredSession = false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings();
    final events =
        ref.watch(aggregatedCalendarEventsProvider).value ??
        const <CalendarEvent>[];
    final next = _nextEvent(events);
    final tasks = ref.watch(tasksStreamProvider).value ?? const <Task>[];
    final habits = ref.watch(habitsStreamProvider).value ?? const <Habit>[];
    final goals = ref.watch(goalsStreamProvider).value ?? const <Goal>[];
    final routines =
        ref.watch(routinesStreamProvider).value ?? const <Routine>[];
    final today = DateTime(_now.year, _now.month, _now.day);
    final todayTasks = tasks
        .where(
          (t) =>
              t.dueDate == null ||
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) ==
                  today,
        )
        .toList();
    final completedTasks = todayTasks.where((t) => t.isCompleted).length;
    final activeHabits = habits.where((h) => !h.archived).toList();
    final routineContents = {
      for (final r in routines.where((r) => r.isActive))
        r.id: RoutineContent.parse(r.description),
    };
    final routineTotal = routineContents.values.fold<int>(
      0,
      (sum, content) => sum + content.steps.length,
    );
    final routineDone = routineContents.values.fold<int>(
      0,
      (sum, content) => sum + content.doneCount,
    );
    final focusEnd = settings.focusSessionEndsAt;
    final focusHistory = ref.watch(recentFocusSessionsProvider).value ??
        const <FocusSession>[];
    final midnight = settings.clockStyle == 'midnight';
    final minimal = settings.clockStyle == 'minimal';
    // A fixed rich surface prevents dark-theme foreground colors being drawn
    // on a light accent card (the blank clock panel shown in the report).
    final cardColor = midnight
        ? const Color(0xFF101827)
        : minimal
            ? context.uiColors.surface
            : const Color(0xFF4E46C7);
    final foreground = minimal ? context.uiColors.foreground : Colors.white;
    return UiPage(
      header: const UiHeader(
        title: 'Clock',
        subtitle: 'Time, focus, and what’s next.',
        leading: QuietNoteMark(size: 38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                Text(
                  DateFormat('HH:mm:ss').format(_now),
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -2,
                    color: foreground,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('EEEE, MMMM d').format(_now),
                  style: TextStyle(color: foreground.withValues(alpha: 0.76)),
                ),
              ],
            ),
          ),
          if (focusEnd != null && focusEnd.isAfter(_now)) ...[
            const SizedBox(height: 16),
            _FocusLiveCard(end: focusEnd, now: _now, onCancel: _cancelFocus),
          ],
          const SizedBox(height: 18),
          Text('Live progress', style: context.uiText.bodyStrong),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _LiveMetric(
                  icon: Icons.check_circle_outline,
                  label: 'Tasks',
                  value: '$completedTasks/${todayTasks.length}',
                  progress: todayTasks.isEmpty
                      ? 0
                      : completedTasks / todayTasks.length,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LiveMetric(
                  icon: Icons.route_outlined,
                  label: 'Routines',
                  value: routineTotal == 0 ? '—' : '$routineDone/$routineTotal',
                  progress: routineTotal == 0 ? 0 : routineDone / routineTotal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (activeHabits.isEmpty)
            UiCard(
              onTap: () => context.go('/habits'),
              child: const Text('Add a habit to see live progress here.'),
            )
          else
            ...activeHabits.take(3).map((habit) {
              final entries =
                  ref.watch(habitEntriesStreamProvider(habit.id)).value ??
                  const <HabitEntry>[];
              final matching = entries.where(
                (e) =>
                    e.date.year == today.year &&
                    e.date.month == today.month &&
                    e.date.day == today.day,
              );
              final entry = matching.isEmpty ? null : matching.first;
              final target = habit.goalTarget;
              final value =
                  entry?.value ?? (entry?.isDone == true ? (target ?? 1) : 0);
              final progress = target != null && target > 0
                  ? (value / target).clamp(0.0, 1.0)
                  : (entry?.isDone == true ? 1.0 : 0.0);
              final label = target != null
                  ? '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1)}/${target.toStringAsFixed(target == target.roundToDouble() ? 0 : 1)} ${habit.goalUnit ?? ''}'
                        .trim()
                  : (entry?.isDone == true ? 'Done today' : 'Not started');
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: UiCard(
                  onTap: () => ref
                      .read(habitRepositoryProvider)
                      .toggleEntry(habit.id, today),
                  child: Row(
                    children: [
                      UiProgressCircle(
                        value: progress,
                        size: 42,
                        thickness: 5,
                        center: Text(
                          '${(progress * 100).round()}%',
                          style: context.uiText.caption,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(habit.title, style: context.uiText.bodyStrong),
                            Text(label, style: context.uiText.caption),
                          ],
                        ),
                      ),
                      Icon(
                        progress >= 1
                            ? Icons.check_circle
                            : Icons.play_circle_outline,
                        color: context.uiColors.primary,
                      ),
                    ],
                  ),
                ),
              );
            }),
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Goals', style: context.uiText.bodyStrong),
            const SizedBox(height: 8),
            ...goals
                .where((g) => g.progressPercent < 100)
                .take(2)
                .map(
                  (goal) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: UiCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  goal.title,
                                  style: context.uiText.bodyStrong,
                                ),
                                const SizedBox(height: 6),
                                UiProgressBar(
                                  value: goal.progressPercent / 100,
                                  showValue: false,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            '${goal.progressPercent}%',
                            style: context.uiText.bodyStrong,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
          const SizedBox(height: 18),
          Text('Clock style', style: context.uiText.bodyStrong),
          const SizedBox(height: 8),
          UiToggleGroup<String>(
            variant: UiToggleGroupVariant.segmented,
            expand: true,
            value: settings.clockStyle,
            options: const [
              UiToggleOption(value: 'digital', label: 'Digital'),
              UiToggleOption(value: 'midnight', label: 'Midnight'),
              UiToggleOption(value: 'minimal', label: 'Minimal'),
            ],
            onChanged: (value) => ref
                .read(settingsProvider.notifier)
                .update((s) => s.copyWith(clockStyle: value)),
          ),
          const SizedBox(height: 20),
          UiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timer_outlined, color: context.uiColors.primary),
                    const SizedBox(width: 8),
                    Text('Focus timer', style: context.uiText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 12),
                UiToggleGroup<int>(
                  variant: UiToggleGroupVariant.segmented,
                  expand: true,
                  value: _minutes,
                  options: const [
                    UiToggleOption(value: 5, label: '5 min'),
                    UiToggleOption(value: 25, label: '25 min'),
                    UiToggleOption(value: 50, label: '50 min'),
                  ],
                  onChanged: (value) => setState(() => _minutes = value),
                ),
                const SizedBox(height: 14),
                UiButton(
                  label: 'Start $_minutes-minute timer',
                  leadingIcon: Icons.play_arrow_rounded,
                  loading: _scheduling,
                  onPressed: _scheduling ? null : _startTimer,
                ),
              ],
            ),
          ),
          if (focusHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${focusHistory.where((s) => s.status == 'completed').length} completed focus sessions saved',
              style: context.uiText.caption,
            ),
          ],
          const SizedBox(height: 20),
          Text('Up next', style: context.uiText.bodyStrong),
          const SizedBox(height: 8),
          if (next == null)
            const UiEmptyState(
              title: 'Nothing scheduled',
              message: 'Your next task or event will appear here.',
              icon: Icons.event_available_outlined,
            )
          else
            UiCard(
              child: Row(
                children: [
                  Icon(Icons.event_outlined, color: context.uiColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(next.title, style: context.uiText.bodyStrong),
                        Text(
                          DateFormat('EEE, j:mm a').format(next.startTime),
                          style: context.uiText.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  CalendarEvent? _nextEvent(List<CalendarEvent> events) {
    final upcoming =
        events
            .where((event) => event.startTime.isAfter(DateTime.now()))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}

class _FocusLiveCard extends StatelessWidget {
  const _FocusLiveCard({
    required this.end,
    required this.now,
    required this.onCancel,
  });
  final DateTime end;
  final DateTime now;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = end.difference(now).inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return UiCard(
      accentColor: context.uiColors.primary,
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: context.uiColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Focus session in progress',
                  style: context.uiText.bodyStrong,
                ),
                Text(
                  '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining',
                  style: context.uiText.caption,
                ),
              ],
            ),
          ),
          UiIconButton(
            icon: Icons.stop_circle_outlined,
            tooltip: 'End focus session',
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}

class _LiveMetric extends StatelessWidget {
  const _LiveMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
  });
  final IconData icon;
  final String label;
  final String value;
  final double progress;
  @override
  Widget build(BuildContext context) => UiCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: context.uiColors.primary),
        const SizedBox(height: 8),
        Text(value, style: context.uiText.heading),
        Text(label, style: context.uiText.caption),
        const SizedBox(height: 8),
        UiProgressBar(value: progress, showValue: false),
      ],
    ),
  );
}
