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
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/focus_preset.dart';
import 'package:quietnote/features/routines/routines_screen.dart';
import 'package:quietnote/core/audio/ambient_audio_service.dart';

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

  FocusPreset? _preset;
  String _phase = 'work';

  // Linking targets
  String? _selectedCourseId;
  String? _selectedTaskId;
  String? _selectedHabitId;

  // Soundscape
  String _activeAmbientSound = 'none';

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
    AmbientAudioService().stop();
    super.dispose();
  }

  Future<void> _selectAmbientSound(String soundKey) async {
    setState(() => _activeAmbientSound = soundKey);
    await AmbientAudioService().setSound(soundKey);
  }

  FocusPreset? _selectedPreset(AppSettings settings) =>
      _preset ?? focusPresetFromId(settings.lastUsedPresetId);

  Future<void> _pickPreset(FocusPreset preset) async {
    setState(() {
      _preset = preset;
      final cfg = preset.config;
      if (cfg != null) _minutes = cfg.work;
    });
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

    await ref.read(focusSessionRepositoryProvider).start(
          endsAt: scheduled,
          minutes: minutes,
          presetId: preset?.name,
          courseId: _selectedCourseId,
          taskId: _selectedTaskId,
          habitId: _selectedHabitId,
        );
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));
    if (!mounted) return;
    setState(() {
      _scheduling = false;
      _phase = 'work';
    });
    UiToast.show(
      context,
      title: 'Focus session started',
      message: 'Ends at ${DateFormat.jm().format(scheduled)}. Saved to focus history.',
      intent: UiIntent.success,
      icon: Icons.timer_outlined,
    );
    unawaited(_scheduleAlert(
      scheduled,
      'Focus timer complete',
      'Your $minutes-minute focus session is complete.',
    ));
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
    UiToast.show(
      context,
      title: 'Timer is running',
      message: 'Enable notifications in Settings to receive completion alert.',
      intent: UiIntent.warning,
      icon: Icons.notifications_off_outlined,
    );
  }

  Future<void> _cancelFocus() async {
    await NotificationService().clearFocusTimerStatus();
    await ref.read(focusSessionRepositoryProvider).finishActive(cancelled: true);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(clearFocusSession: true));
    if (mounted) setState(() => _phase = 'work');
  }

  Future<void> _finishSession({bool cancelled = false}) async {
    final active = ref.read(activeFocusSessionProvider).value;
    await ref.read(focusSessionRepositoryProvider).finishActive(cancelled: cancelled);
    await NotificationService().clearFocusTimerStatus();
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(clearFocusSession: true));
    if (mounted) setState(() => _phase = 'work');

    if (!cancelled && active != null && mounted) {
      await _promptPostSessionReflection(active);
    }
  }

  Future<void> _promptPostSessionReflection(FocusSession session) async {
    final controller = TextEditingController();
    final saveToJournal = ValueNotifier<bool>(false);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.stars, color: context.uiColors.primary),
            const SizedBox(width: 8),
            const Text('Focus Session Complete!'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Great job staying focused for ${session.durationMinutes} minutes! Write a quick reflection on what you accomplished:',
              style: context.uiText.body,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'e.g. Completed Chapter 3 notes, solved 5 problem set questions.',
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: saveToJournal,
              builder: (context, value, _) {
                return CheckboxListTile(
                  value: value,
                  onChanged: (v) => saveToJournal.value = v ?? false,
                  title: const Text('Save as Journal Entry'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Skip')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Reflection')),
        ],
      ),
    );

    if (ok == true && controller.text.trim().isNotEmpty) {
      final reflectionText = controller.text.trim();
      await ref.read(focusSessionRepositoryProvider).saveReflection(session.id, reflectionText);

      if (saveToJournal.value) {
        await ref.read(journalRepositoryProvider).addEntry(
              reflectionText,
              title: 'Focus Session Reflection',
              tags: ['Focus', if (session.courseId != null) 'Course'],
            );
      }
      if (mounted) {
        UiToast.show(context, title: 'Reflection saved', intent: UiIntent.success);
      }
    }
  }

  Future<void> _continuePhase(
    int minutes,
    String nextPhase,
    String alertTitle,
    String alertBody,
  ) async {
    final scheduled = DateTime.now().add(Duration(minutes: minutes));
    await ref.read(focusSessionRepositoryProvider).extendActive(endsAt: scheduled);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));
    if (mounted) setState(() => _phase = nextPhase);
    unawaited(_scheduleAlert(scheduled, alertTitle, alertBody));
    unawaited(NotificationService().showFocusTimerStatus(scheduled));
  }

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
        ref.watch(aggregatedCalendarEventsProvider).value ?? const <CalendarEvent>[];
    final next = _nextEvent(events);
    final tasks = ref.watch(tasksStreamProvider).value ?? const <Task>[];
    final habits = ref.watch(habitsStreamProvider).value ?? const <Habit>[];
    final goals = ref.watch(goalsStreamProvider).value ?? const <Goal>[];
    final courses = ref.watch(coursesStreamProvider).value ?? const <Course>[];
    final routines = ref.watch(routinesStreamProvider).value ?? const <Routine>[];
    final today = DateTime(_now.year, _now.month, _now.day);

    final todayTasks = tasks
        .where(
          (t) =>
              t.dueDate == null ||
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day) == today,
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
    final focusHistory = ref.watch(recentFocusSessionsProvider).value ?? const <FocusSession>[];

    final selectedPreset = _selectedPreset(settings);
    final presetCfg = selectedPreset?.config;
    final effectiveMinutes = presetCfg?.work ?? _minutes;

    final totalCyclesInHistory = focusHistory.fold<int>(
      0,
      (sum, s) => sum + s.cyclesCompleted,
    );

    final midnight = settings.clockStyle == 'midnight';
    final minimal = settings.clockStyle == 'minimal';
    final cardColor = midnight
        ? const Color(0xFF101827)
        : minimal
            ? context.uiColors.surface
            : const Color(0xFF4E46C7);
    final foreground = minimal ? context.uiColors.foreground : Colors.white;

    return UiPage(
      header: const UiHeader(
        title: 'Clock & Focus',
        subtitle: 'Time your deep work sessions and boost concentration.',
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
          UiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.surround_sound_outlined, color: context.uiColors.primary),
                    const SizedBox(width: 8),
                    Text('Ambient Soundscape', style: context.uiText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _SoundChip(
                        label: 'None',
                        icon: Icons.volume_off_outlined,
                        selected: _activeAmbientSound == 'none',
                        onTap: () => _selectAmbientSound('none'),
                      ),
                      const SizedBox(width: 8),
                      _SoundChip(
                        label: 'Rain',
                        icon: Icons.water_drop_outlined,
                        selected: _activeAmbientSound == 'rain',
                        onTap: () => _selectAmbientSound('rain'),
                      ),
                      const SizedBox(width: 8),
                      _SoundChip(
                        label: 'Waves',
                        icon: Icons.waves,
                        selected: _activeAmbientSound == 'waves',
                        onTap: () => _selectAmbientSound('waves'),
                      ),
                      const SizedBox(width: 8),
                      _SoundChip(
                        label: 'White Noise',
                        icon: Icons.graphic_eq,
                        selected: _activeAmbientSound == 'whitenoise',
                        onTap: () => _selectAmbientSound('whitenoise'),
                      ),
                      const SizedBox(width: 8),
                      _SoundChip(
                        label: 'Cafe',
                        icon: Icons.local_cafe_outlined,
                        selected: _activeAmbientSound == 'cafe',
                        onTap: () => _selectAmbientSound('cafe'),
                      ),
                      const SizedBox(width: 8),
                      _SoundChip(
                        label: 'Synth Focus',
                        icon: Icons.music_note_outlined,
                        selected: _activeAmbientSound == 'synth',
                        onTap: () => _selectAmbientSound('synth'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
                  progress: todayTasks.isEmpty ? 0 : completedTasks / todayTasks.length,
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
                  ref.watch(habitEntriesStreamProvider(habit.id)).value ?? const <HabitEntry>[];
              final matching = entries.where(
                (e) =>
                    e.date.year == today.year &&
                    e.date.month == today.month &&
                    e.date.day == today.day,
              );
              final entry = matching.isEmpty ? null : matching.first;
              final target = habit.goalTarget;
              final value = entry?.value ?? (entry?.isDone == true ? (target ?? 1) : 0);
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
                  onTap: () =>
                      ref.read(habitRepositoryProvider).toggleEntry(habit.id, today),
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
                        progress >= 1 ? Icons.check_circle : Icons.play_circle_outline,
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
                if (courses.isNotEmpty) ...[
                  Text('Focus target (Course / Class)', style: context.uiText.caption),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedCourseId,
                    decoration: const InputDecoration(
                      hintText: 'Select course to link focus session...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('General Focus (No Course)'),
                      ),
                      ...courses.map((c) => DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.code != null ? '${c.code} - ${c.name}' : c.name),
                          )),
                    ],
                    onChanged: (val) => setState(() => _selectedCourseId = val),
                  ),
                  const SizedBox(height: 12),
                ],
                if (tasks.isNotEmpty) ...[
                  Text('Focus target (Task / Assignment)', style: context.uiText.caption),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedTaskId,
                    decoration: const InputDecoration(
                      hintText: 'Select task to link focus session...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('General Focus (No Task)'),
                      ),
                      ...tasks.where((t) => !t.isCompleted).map((t) => DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.title, overflow: TextOverflow.ellipsis),
                          )),
                    ],
                    onChanged: (val) => setState(() => _selectedTaskId = val),
                  ),
                  const SizedBox(height: 12),
                ],
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
            const SizedBox(height: 16),
            Row(
              children: [
                Text('Focus History', style: context.uiText.bodyStrong),
                const Spacer(),
                Text(
                  '${focusHistory.where((s) => s.status == 'completed').length} completed ($totalCyclesInHistory cycles)',
                  style: context.uiText.caption,
                ),
              ],
            ),
            const SizedBox(height: 10),
            ...focusHistory.take(5).map((s) {
              final course = courses.where((c) => c.id == s.courseId).firstOrNull;
              final task = tasks.where((t) => t.id == s.taskId).firstOrNull;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiCard(
                  child: Row(
                    children: [
                      Icon(
                        s.status == 'completed' ? Icons.check_circle : Icons.cancel,
                        color: s.status == 'completed'
                            ? context.uiColors.primary
                            : context.uiColors.destructive,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${s.durationMinutes} min focus session', style: context.uiText.bodyStrong),
                                if (course != null) ...[
                                  const SizedBox(width: 8),
                                  UiBadge(
                                    label: course.code ?? course.name,
                                    intent: UiIntent.primary,
                                    size: UiSize.xs,
                                  ),
                                ],
                              ],
                            ),
                            if (task != null) ...[
                              const SizedBox(height: 2),
                              Text('Task: ${task.title}', style: context.uiText.caption),
                            ],
                            Text(
                              DateFormat.yMMMd().add_jm().format(s.startedAt),
                              style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted),
                            ),
                            if (s.reflection != null && s.reflection!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('"${s.reflection}"', style: context.uiText.caption.copyWith(fontStyle: FontStyle.italic)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
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
        events.where((event) => event.startTime.isAfter(DateTime.now())).toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));
    return upcoming.isEmpty ? null : upcoming.first;
  }
}

class _SoundChip extends StatelessWidget {
  const _SoundChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final activeBg = c.primary;
    final activeFg = c.onPrimary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeBg : c.surfaceMuted,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? activeBg : c.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? activeFg : c.foregroundMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: context.uiText.caption.copyWith(
                color: selected ? activeFg : c.foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
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
