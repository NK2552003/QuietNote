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
import 'package:quietnote/features/clock/focus_preset.dart';
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

  /// `null` until the student taps a chip this session — falls back to the
  /// persisted `lastUsedPresetId` (see [_selectedPreset]) so the choice
  /// survives an app restart mid-decision.
  FocusPreset? _preset;

  /// Which half of a chained Pomodoro-style session is currently running.
  /// Reset to 'work' whenever a fresh (non-chained) timer is started.
  String _phase = 'work';

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final end = ref.read(settingsProvider).value?.focusSessionEndsAt;
      if (end != null && !end.isAfter(_now)) {
        unawaited(_handleTimerExpiry());
      }
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  /// The chip the student picked this session, falling back to whatever was
  /// persisted last time so the Clock screen re-opens with the same choice.
  FocusPreset? _selectedPreset(AppSettings settings) =>
      _preset ?? focusPresetFromId(settings.lastUsedPresetId);

  Future<void> _pickPreset(FocusPreset preset) async {
    setState(() {
      _preset = preset;
      final cfg = preset.config;
      if (cfg != null) _minutes = cfg.work;
    });
    // Persisted immediately (not just on session start) so the choice
    // survives an app restart mid-decision.
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(lastUsedPresetId: preset.name));
  }

  Future<void> _startTimer() async {
    if (_scheduling) return;
    setState(() => _scheduling = true);
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final preset = _selectedPreset(settings);
    final minutes = preset?.config?.work ?? _minutes;
    final scheduled = DateTime.now().add(Duration(minutes: minutes));
    // Persist and paint the timer first. Notification permission or platform
    // scheduling must never make the primary Start action feel unresponsive.
    await ref.read(focusSessionRepositoryProvider).start(
          endsAt: scheduled,
          minutes: minutes,
          presetId: preset?.name,
        );
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));
    if (!mounted) return;
    setState(() {
      _scheduling = false;
      _phase = 'work';
    });
    UiToast.show(context,
      title: 'Focus session started',
      message: 'Ends at ${DateFormat.jm().format(scheduled)}. It is saved to your focus history.',
      intent: UiIntent.success, icon: Icons.timer_outlined);
    // Scheduling is deliberately non-blocking: the running timer remains
    // correct even if a device has notifications disabled.
    unawaited(_scheduleAlert(scheduled, 'Focus timer complete',
        'Your $minutes-minute focus session is complete.'));
    unawaited(NotificationService().showFocusTimerStatus(scheduled));
  }

  Future<void> _scheduleAlert(DateTime scheduled, String title, String body) async {
    final ok = await NotificationService().scheduleReminder(
      NotificationService.focusStatusNotificationId,
      title,
      body,
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
    if (mounted) setState(() => _phase = 'work');
  }

  /// Ends the active session outright — used when a chained phase (work or
  /// break) expires and the student declines to continue.
  Future<void> _finishSession({bool cancelled = false}) async {
    await ref.read(focusSessionRepositoryProvider).finishActive(cancelled: cancelled);
    await NotificationService().clearFocusTimerStatus();
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(clearFocusSession: true));
    if (mounted) setState(() => _phase = 'work');
  }

  /// Extends the active session row into its next phase (work -> break, or
  /// break -> next work) instead of finishing it, so the chain stays one
  /// history entry.
  Future<void> _continuePhase(int minutes, String nextPhase, String alertTitle, String alertBody) async {
    final scheduled = DateTime.now().add(Duration(minutes: minutes));
    await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: scheduled);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));
    if (mounted) setState(() => _phase = nextPhase);
    unawaited(_scheduleAlert(scheduled, alertTitle, alertBody));
    unawaited(NotificationService().showFocusTimerStatus(scheduled));
  }

  /// Fires when the running timer (work or break phase) hits zero. For a
  /// Pomodoro-style preset this offers to chain into the next phase instead
  /// of just marking the session done.
  Future<void> _handleTimerExpiry() async {
    if (_finishingExpiredSession) return;
    _finishingExpiredSession = true;
    final active = ref.read(activeFocusSessionProvider).value;
    final cfg = focusPresetFromId(active?.presetId)?.config;

    if (cfg != null && cfg.brk > 0 && _phase == 'work') {
      _finishingExpiredSession = false;
      await _promptStartBreak(cfg);
      return;
    }
    if (cfg != null && cfg.brk > 0 && _phase == 'break') {
      _finishingExpiredSession = false;
      await _promptStartNextWork(cfg);
      return;
    }
    await _finishSession();
    _finishingExpiredSession = false;
  }

  Future<void> _promptStartBreak(FocusPresetConfig cfg) async {
    if (!mounted) return;
    final start = await UiDialog.confirm(
      context,
      title: 'Work interval complete',
      description: 'Start your ${cfg.brk}-minute break?',
      confirmLabel: 'Start break',
      cancelLabel: 'Skip break',
    );
    if (!mounted) return;
    if (start) {
      await _continuePhase(
        cfg.brk,
        'break',
        'Break complete',
        'Your ${cfg.brk}-minute break is complete.',
      );
    } else {
      await _finishSession();
    }
  }

  Future<void> _promptStartNextWork(FocusPresetConfig cfg) async {
    // A break finishing is what closes out a full work -> break -> work
    // loop, regardless of whether the student continues into another one.
    await ref.read(focusSessionRepositoryProvider).incrementCycle();
    if (!mounted) return;
    final start = await UiDialog.confirm(
      context,
      title: 'Break complete',
      description: 'Start the next ${cfg.work}-minute work interval?',
      confirmLabel: 'Start work',
      cancelLabel: 'End session',
    );
    if (!mounted) return;
    if (start) {
      await _continuePhase(
        cfg.work,
        'work',
        'Focus timer complete',
        'Your ${cfg.work}-minute focus session is complete.',
      );
    } else {
      await _finishSession();
    }
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
    final activeSession = ref.watch(activeFocusSessionProvider).value;
    final focusHistory = ref.watch(recentFocusSessionsProvider).value ??
        const <FocusSession>[];
    final selectedPreset = _selectedPreset(settings);
    final presetCfg = selectedPreset?.config;
    final effectiveMinutes = presetCfg?.work ?? _minutes;
    final totalCyclesInHistory = focusHistory.fold<int>(
      0,
      (sum, s) => sum + s.cyclesCompleted,
    );
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
            _FocusLiveCard(
              end: focusEnd,
              now: _now,
              onCancel: _cancelFocus,
              phase: _phase,
              cyclesCompleted: activeSession?.cyclesCompleted ?? 0,
              presetLabel: focusPresetFromId(activeSession?.presetId)?.chipLabel,
            ),
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
                Text('Study preset', style: context.uiText.caption),
                const SizedBox(height: 8),
                UiToggleGroup<FocusPreset>(
                  variant: UiToggleGroupVariant.segmented,
                  expand: true,
                  scrollableOnMobile: true,
                  value: selectedPreset,
                  options: [
                    for (final preset in FocusPreset.values)
                      UiToggleOption(
                        value: preset,
                        label: preset.chipLabel,
                      ),
                  ],
                  onChanged: _pickPreset,
                ),
                const SizedBox(height: 14),
                if (selectedPreset != null && selectedPreset != FocusPreset.custom) ...[
                  UiCard(
                    child: Row(
                      children: [
                        Icon(Icons.route_outlined, size: 18, color: context.uiColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${presetCfg!.label} — work ${presetCfg.work} min'
                            '${presetCfg.brk > 0 ? ', break ${presetCfg.brk} min' : ' (no break)'}',
                            style: context.uiText.caption,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else
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
              SizedBox(
                  width: double.infinity,
                  child: UiButton(
                    label: 'Start $effectiveMinutes-minute timer',
                    leadingIcon: Icons.play_arrow_rounded,
                    loading: _scheduling,
                    onPressed: _scheduling ? null : _startTimer,
                  ),
                ),
              ],
            ),
          ),
          if (focusHistory.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${focusHistory.where((s) => s.status == 'completed').length} completed focus sessions saved'
              '${totalCyclesInHistory > 0 ? ' · $totalCyclesInHistory study cycles completed' : ''}',
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
    required this.phase,
    required this.cyclesCompleted,
    this.presetLabel,
  });
  final DateTime end;
  final DateTime now;
  final VoidCallback onCancel;
  final String phase;
  final int cyclesCompleted;
  final String? presetLabel;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = end.difference(now).inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final isBreak = phase == 'break';
    return UiCard(
      accentColor: context.uiColors.primary,
      child: Row(
        children: [
          Icon(
            isBreak ? Icons.local_cafe_outlined : Icons.timer_outlined,
            color: context.uiColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isBreak ? 'Break in progress' : 'Focus session in progress',
                      style: context.uiText.bodyStrong,
                    ),
                    if (presetLabel != null) ...[
                      const SizedBox(width: 8),
                      UiBadge(label: presetLabel!, size: UiSize.xs),
                    ],
                    if (cyclesCompleted > 0) ...[
                      const SizedBox(width: 6),
                      UiBadge(
                        label: 'Cycle ${cyclesCompleted + 1}',
                        intent: UiIntent.primary,
                        size: UiSize.xs,
                      ),
                    ],
                  ],
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
