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
import 'package:quietnote/core/focus/focus_timer_service.dart';
import 'package:quietnote/core/notifications/notification_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/clock/focus_preset.dart';
import 'package:quietnote/features/routines/routines_screen.dart';
import 'package:quietnote/core/audio/ambient_audio_service.dart';

import 'focus_history_screen.dart';
import 'zen_focus_screen.dart';
import 'package:flutter/services.dart';

class ClockScreen extends ConsumerStatefulWidget {
  const ClockScreen({super.key});
  @override
  ConsumerState<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends ConsumerState<ClockScreen> {
  late DateTime _now;
  Timer? _ticker;
  int _minutes = 25;
  int _customBreakMinutes = 5;
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
    AmbientAudioService().stopAlarm();
    super.dispose();
  }

  Future<void> _selectAmbientSound(String soundKey) async {
    HapticFeedback.selectionClick();
    setState(() => _activeAmbientSound = soundKey);
    await AmbientAudioService().setSound(soundKey);
  }

  FocusPreset? _selectedPreset(AppSettings settings) =>
      _preset ?? focusPresetFromId(settings.lastUsedPresetId);

  Future<void> _pickPreset(FocusPreset preset) async {
    HapticFeedback.selectionClick();
    if (preset == FocusPreset.custom) {
      setState(() => _preset = preset);
      await _showCustomDurationDialog();
      return;
    }
    setState(() {
      _preset = preset;
      final cfg = preset.config;
      if (cfg != null) _minutes = cfg.work;
    });
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(lastUsedPresetId: preset.name));
  }

  Future<void> _showCustomDurationDialog() async {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final initialWork = _preset == FocusPreset.custom
        ? _minutes
        : (settings.focusSessionIntervalMinutes > 0 ? settings.focusSessionIntervalMinutes : _minutes);
    final initialBreak = _preset == FocusPreset.custom
        ? _customBreakMinutes
        : (settings.focusSessionBreakMinutes > 0 ? settings.focusSessionBreakMinutes : _customBreakMinutes);

    final workCtrl = TextEditingController(text: '$initialWork');
    final breakCtrl = TextEditingController(text: '$initialBreak');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.edit_calendar_outlined, color: context.uiColors.primary),
            const SizedBox(width: 8),
            const Text('Custom Duration'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set your customized focus and break interval:',
                style: context.uiText.body),
            const SizedBox(height: 16),
            TextField(
              controller: workCtrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Focus / Work Duration (minutes)',
                hintText: 'e.g. 35',
                prefixIcon: Icon(Icons.timer_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: breakCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Break Duration (minutes, 0 for none)',
                hintText: 'e.g. 5',
                prefixIcon: Icon(Icons.local_cafe_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Set Duration'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final work = int.tryParse(workCtrl.text.trim()) ?? _minutes;
      final brk = int.tryParse(breakCtrl.text.trim()) ?? _customBreakMinutes;
      if (work > 0) {
        final clampedWork = work.clamp(1, 300);
        final clampedBreak = brk.clamp(0, 120);
        setState(() {
          _minutes = clampedWork;
          _customBreakMinutes = clampedBreak;
          _preset = FocusPreset.custom;
        });
        await ref.read(settingsProvider.notifier).update(
              (s) => s.copyWith(
                lastUsedPresetId: FocusPreset.custom.name,
                focusSessionIntervalMinutes: clampedWork,
                focusSessionBreakMinutes: clampedBreak,
              ),
            );
      }
    }
  }

  Future<void> _extendFocus(int mins) async {
    HapticFeedback.lightImpact();
    final currentSettings = ref.read(settingsProvider).value;
    final baseEnd = currentSettings?.focusSessionEndsAt ?? DateTime.now();
    final scheduled = baseEnd.add(Duration(minutes: mins));
    await ref
        .read(focusSessionRepositoryProvider)
        .extendActive(endsAt: scheduled);
    await ref
        .read(settingsProvider.notifier)
        .update((s) => s.copyWith(focusSessionEndsAt: scheduled));

    final activeSession = ref.read(activeFocusSessionProvider).value;
    final courses = ref.read(coursesStreamProvider).value ?? const <Course>[];
    final tasks = ref.read(tasksStreamProvider).value ?? const <Task>[];
    final course = courses.where((c) => c.id == activeSession?.courseId).firstOrNull;
    final task = tasks.where((t) => t.id == activeSession?.taskId).firstOrNull;
    final linkedTitle = course != null ? (course.code ?? course.name) : task?.title;

    unawaited(NotificationService().showFocusTimerStatus(
      scheduled,
      phase: _phase,
      presetLabel: focusPresetFromId(activeSession?.presetId)?.chipLabel,
      linkedTitle: linkedTitle,
    ));
    unawaited(_scheduleAlert(
      scheduled,
      'Focus timer complete',
      'Your focus session is complete.',
    ));
    if (mounted) {
      setState(() {});
      UiToast.show(
        context,
        title: 'Extended by +$mins min',
        message: 'Focus session will now complete at ${DateFormat.jm().format(scheduled)}.',
        intent: UiIntent.primary,
        icon: Icons.more_time_rounded,
      );
    }
  }

  void _openZenMode(DateTime end, String? presetLabel, String? linkedTitle, {DateTime? startedAt}) {
    ZenFocusScreen.open(
      context,
      ref,
      end: end,
      startedAt: startedAt,
      presetLabel: presetLabel,
      linkedTitle: linkedTitle,
    );
  }

  Future<void> _startTimer() async {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final preset = _selectedPreset(settings);
    final int workMins = (preset != null && preset != FocusPreset.custom && preset.config != null)
        ? preset.config!.work
        : _minutes;
    await _startFocus(workMins);
  }

  Future<void> _startFocus(int minutes) async {
    final settings = ref.read(settingsProvider).value ?? const AppSettings();
    final preset = _preset ?? _selectedPreset(settings);
    final int effectiveMinutes = (preset == FocusPreset.custom || preset == null)
        ? (minutes > 0 ? minutes : (_minutes > 0 ? _minutes : 25))
        : (preset.config?.work ?? minutes);
    final int breakMinutes = (preset == null || preset == FocusPreset.custom)
        ? (settings.focusSessionBreakMinutes > 0 ? settings.focusSessionBreakMinutes : _customBreakMinutes)
        : (preset.config?.brk ?? _customBreakMinutes);
    setState(() => _scheduling = true);

    final courses = ref.read(coursesStreamProvider).value ?? const <Course>[];
    final tasks = ref.read(tasksStreamProvider).value ?? const <Task>[];
    final course =
        courses.where((c) => c.id == _selectedCourseId).firstOrNull;
    final task = tasks.where((t) => t.id == _selectedTaskId).firstOrNull;
    final linkedTitle =
        course != null ? (course.code ?? course.name) : task?.title;

    await FocusTimerService().startSession(
      ref,
      workMinutes: effectiveMinutes,
      breakMinutes: breakMinutes,
      preset: preset,
      courseId: _selectedCourseId,
      taskId: _selectedTaskId,
      habitId: _selectedHabitId,
      linkedTitle: linkedTitle,
    );

    if (!mounted) return;
    setState(() {
      _scheduling = false;
      _phase = 'work';
    });

    final scheduled = DateTime.now().add(Duration(minutes: minutes));
    UiToast.show(
      context,
      title: 'Focus session started',
      message:
          'Ends at ${DateFormat.jm().format(scheduled)}. Saved to focus history.',
      intent: UiIntent.success,
      icon: Icons.timer_outlined,
    );
  }

  Future<void> _scheduleAlert(
      DateTime scheduled, String title, String body) async {
    final ok = await NotificationService().scheduleReminder(
      NotificationService.focusStatusNotificationId,
      title,
      body,
      scheduled,
      feature: NotificationFeature.focus,
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
    HapticFeedback.lightImpact();
    await _finishSession(cancelled: true);
  }

  Future<void> _finishSession({bool? cancelled}) async {
    final active = ref.read(activeFocusSessionProvider).value;
    await FocusTimerService().finishSession(ref, cancelled: cancelled);
    if (mounted) setState(() => _phase = 'work');

    if (cancelled != true && active != null && mounted) {
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
                hintText:
                    'e.g. Completed Chapter 3 notes, solved 5 problem set questions.',
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save Reflection')),
        ],
      ),
    );

    if (ok == true && controller.text.trim().isNotEmpty) {
      final reflectionText = controller.text.trim();
      await ref
          .read(focusSessionRepositoryProvider)
          .saveReflection(session.id, reflectionText);

      if (saveToJournal.value) {
        await ref.read(journalRepositoryProvider).addEntry(
              reflectionText,
              title: 'Focus Session Reflection',
              tags: ['Focus', if (session.courseId != null) 'Course'],
            );
      }
      if (mounted) {
        UiToast.show(context,
            title: 'Reflection saved', intent: UiIntent.success);
      }
    }
  }

  Future<void> _handleTimerExpiry() async {
    if (_finishingExpiredSession) return;
    _finishingExpiredSession = true;
    try {
      await FocusTimerService().handleTimerExpiry(ref, context: context);
      if (mounted) {
        final settings = ref.read(settingsProvider).value;
        setState(() {
          _phase = settings?.focusSessionPhase ?? 'work';
        });
      }
    } finally {
      _finishingExpiredSession = false;
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
          if (focusEnd != null && focusEnd.isAfter(_now)) ...[
            _HeroActiveFocusCard(
              end: focusEnd,
              now: _now,
              startedAt: settings.focusSessionStartedAt ?? activeSession?.startedAt,
              phase: settings.focusSessionPhase,
              cyclesCompleted: activeSession?.cyclesCompleted ?? 0,
              presetLabel: focusPresetFromId(activeSession?.presetId)?.chipLabel,
              linkedTitle: () {
                final course = courses.where((c) => c.id == activeSession?.courseId).firstOrNull;
                final task = tasks.where((t) => t.id == activeSession?.taskId).firstOrNull;
                return course != null ? (course.code ?? course.name) : task?.title;
              }(),
              onCancel: _cancelFocus,
              onExtend: () => _extendFocus(5),
              onZen: () {
                final course = courses.where((c) => c.id == activeSession?.courseId).firstOrNull;
                final task = tasks.where((t) => t.id == activeSession?.taskId).firstOrNull;
                final linkedTitle = course != null
                    ? (course.code ?? course.name)
                    : task?.title;
                _openZenMode(
                  focusEnd,
                  focusPresetFromId(activeSession?.presetId)?.chipLabel,
                  linkedTitle,
                  startedAt: settings.focusSessionStartedAt ?? activeSession?.startedAt,
                );
              },
              onResumeWork: () => FocusTimerService().skipBreakAndStartWork(ref, context: context),
            ),
          ] else ...[
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in FocusPreset.values)
                      _FocusPresetChip(
                        preset: preset,
                        selected: selectedPreset == preset,
                        onTap: () => _pickPreset(preset),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                if (selectedPreset != null && selectedPreset != FocusPreset.custom) ...[
                  UiCard(
                    child: Row(
                      children: [
                        Icon(Icons.route_outlined, size: 18, color: context.uiColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${presetCfg!.label} — work ${presetCfg.work} min'
                                '${presetCfg.brk > 0 ? ', break ${presetCfg.brk} min' : ' (no break)'}',
                                style: context.uiText.bodyStrong,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                presetCfg.subtitle,
                                style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ] else ...[
                  UiCard(
                    child: Row(
                      children: [
                        Icon(Icons.tune_outlined, size: 18, color: context.uiColors.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Custom: $_minutes min focus · $_customBreakMinutes min break',
                            style: context.uiText.bodyStrong,
                          ),
                        ),
                        UiButton(
                          label: 'Edit',
                          variant: UiVariant.ghost,
                          size: UiSize.xs,
                          leadingIcon: Icons.edit_outlined,
                          onPressed: _showCustomDurationDialog,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
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
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => FocusHistoryScreen.show(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Text('Focus History', style: context.uiText.bodyStrong),
                    const SizedBox(width: 6),
                    Icon(Icons.arrow_forward_ios_rounded,
                        size: 12, color: context.uiColors.primary),
                    const Spacer(),
                    Text(
                      '${focusHistory.where((s) => s.status == 'completed').length} completed ($totalCyclesInHistory cycles)',
                      style: context.uiText.caption,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            ...focusHistory.take(5).map((s) {
              final course = courses.where((c) => c.id == s.courseId).firstOrNull;
              final task = tasks.where((t) => t.id == s.taskId).firstOrNull;
              final isActive = s.status == 'active';
              final isCompleted = s.status == 'completed';

              final sessionTotalSec = s.endsAt.difference(s.startedAt).inSeconds;
              final elapsedSec = _now.difference(s.startedAt).inSeconds;
              final sessionProgress = sessionTotalSec > 0
                  ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
                  : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => FocusHistoryScreen.show(context),
                  child: UiCard(
                  child: Row(
                    children: [
                      if (isActive)
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(3),
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: sessionProgress,
                                  strokeWidth: 2.6,
                                  strokeCap: StrokeCap.round,
                                  backgroundColor: context.uiColors.primary
                                      .withValues(alpha: 0.15),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      context.uiColors.primary),
                                ),
                              ),
                            ),
                            Icon(
                              Icons.timer_outlined,
                              size: 11,
                              color: context.uiColors.primary,
                            ),
                          ],
                        )
                      else if (isCompleted)
                        Icon(
                          Icons.check_circle_rounded,
                          color: context.uiColors.primary,
                          size: 22,
                        )
                      else
                        Icon(
                          Icons.cancel_outlined,
                          color: context.uiColors.foregroundMuted,
                          size: 22,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('${s.durationMinutes} min focus session',
                                    style: context.uiText.bodyStrong),
                                const SizedBox(width: 8),
                                if (isActive)
                                  const UiBadge(
                                    label: 'In Progress',
                                    intent: UiIntent.primary,
                                    size: UiSize.xs,
                                  )
                                else if (isCompleted)
                                  const UiBadge(
                                    label: 'Completed',
                                    intent: UiIntent.success,
                                    size: UiSize.xs,
                                  )
                                else
                                  const UiBadge(
                                    label: 'Cancelled',
                                    size: UiSize.xs,
                                  ),
                                if (course != null) ...[
                                  const SizedBox(width: 6),
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

class _HeroActiveFocusCard extends StatelessWidget {
  const _HeroActiveFocusCard({
    required this.end,
    required this.now,
    this.startedAt,
    required this.phase,
    required this.cyclesCompleted,
    this.presetLabel,
    this.linkedTitle,
    required this.onCancel,
    required this.onExtend,
    required this.onZen,
    required this.onResumeWork,
  });

  final DateTime end;
  final DateTime now;
  final DateTime? startedAt;
  final String phase;
  final int cyclesCompleted;
  final String? presetLabel;
  final String? linkedTitle;
  final VoidCallback onCancel;
  final VoidCallback onExtend;
  final VoidCallback onZen;
  final VoidCallback onResumeWork;

  @override
  Widget build(BuildContext context) {
    final totalSeconds = end.difference(now).inSeconds.clamp(0, 24 * 60 * 60);
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final isBreak = phase == 'break';
    final accentColor = isBreak ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);

    final effectiveStart = startedAt ??
        end.subtract(
          Duration(
            seconds: (totalSeconds > 0 ? totalSeconds : 25 * 60),
          ),
        );
    final sessionTotalSec = end.difference(effectiveStart).inSeconds;
    final elapsedSec = now.difference(effectiveStart).inSeconds;
    final progress = sessionTotalSec > 0
        ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF101827),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isBreak ? Icons.local_cafe_outlined : Icons.timer_outlined,
                      size: 13,
                      color: accentColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isBreak ? 'Break Time' : (presetLabel ?? 'Deep Focus'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (cyclesCompleted > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Cycle ${cyclesCompleted + 1}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: SizedBox(
                  width: 140,
                  height: 140,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6.0,
                    strokeCap: StrokeCap.round,
                    backgroundColor: accentColor.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      color: Colors.white,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBreak ? 'Remaining' : 'Focus Time',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (linkedTitle != null) ...[
            const SizedBox(height: 14),
            Text(
              linkedTitle!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isBreak) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 16),
                  label: const Text('Resume Focus'),
                  onPressed: onResumeWork,
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.more_time_rounded, size: 15),
                label: const Text('+5m'),
                onPressed: onExtend,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.fullscreen_outlined, size: 15),
                label: const Text('Zen'),
                onPressed: onZen,
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'End focus session',
                icon: const Icon(Icons.stop_circle_outlined, color: Colors.redAccent),
                onPressed: onCancel,
              ),
            ],
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

class _FocusPresetChip extends StatelessWidget {
  const _FocusPresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final FocusPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.primary.withValues(alpha: 0.16)
              : c.surfaceHover.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              preset.icon,
              size: 15,
              color: selected ? c.primary : c.foregroundMuted,
            ),
            const SizedBox(width: 6),
            Text(
              preset.chipLabel,
              style: context.uiText.caption.copyWith(
                color: selected ? c.primary : c.foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
