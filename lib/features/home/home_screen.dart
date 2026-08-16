import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/database/repositories/focus_session_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/focus/focus_timer_service.dart';
import 'package:quietnote/core/settings/app_settings.dart';
import 'package:quietnote/core/settings/settings_repository.dart';
import 'package:quietnote/features/ai/local_ai_engine.dart';
import 'package:quietnote/features/clock/focus_history_screen.dart';
import 'package:quietnote/features/clock/focus_preset.dart';
import 'package:quietnote/features/clock/zen_focus_screen.dart';

/// Which calendar day the Today view is currently showing.
final selectedDayProvider = StateProvider<DateTime>(
  (ref) => _dateOnly(DateTime.now()),
);

/// Active filter category on the Today Agenda
final homeAgendaFilterProvider = StateProvider<String>((ref) => 'all');

/// Session-only "done today" state for routines.
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
    this.tag,
  });

  final _TodayKind kind;
  final String id;
  final String title;
  final String? subtitle;
  final String? timeLabel;
  final bool done;
  final VoidCallback onToggle;
  final Color? color;
  final String? tag;
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

    // Watch all 11 core data streams
    final tasksAsync = ref.watch(tasksStreamProvider);
    final habitsAsync = ref.watch(habitsStreamProvider);
    final routinesAsync = ref.watch(routinesStreamProvider);
    final eventsAsync = ref.watch(aggregatedCalendarEventsProvider);
    final notesAsync = ref.watch(notesStreamProvider);
    final journalAsync = ref.watch(journalStreamProvider);
    final coursesAsync = ref.watch(coursesStreamProvider);
    final goalsAsync = ref.watch(goalsStreamProvider);
    final decksAsync = ref.watch(flashcardDecksStreamProvider);
    final dueCardsAsync = ref.watch(dueFlashcardsProvider(''));
    final activeFocusSession = ref.watch(activeFocusSessionProvider).value;
    final focusHistory = ref.watch(allFocusSessionsProvider).value ?? const [];

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

    final name = settings.displayName.trim();
    final greetingText = name.isEmpty ? _greeting() : '${_greeting()}, $name';

    return UiPage(
      header: UiHeader(
        title: greetingText,
        subtitle:
            '${DateFormat('EEEE, MMMM d').format(selectedDay)} · Daily momentum & study hub',
        actions: [
          UiIconButton(
            icon: Icons.search_rounded,
            tooltip: 'Omni Search',
            onPressed: () => context.push('/search'),
          ),
          UiIconButton(
            icon: Icons.auto_awesome_rounded,
            tooltip: 'Ask AI Assistant',
            onPressed: () => context.push('/ai'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Interactive 7-Day Week Strip
          _DateStrip(
            selected: selectedDay,
            onSelect: (d) {
              HapticFeedback.selectionClick();
              ref.read(selectedDayProvider.notifier).state = d;
            },
          ),
          const SizedBox(height: 14),

          // 2. AI Model setup banner (if missing)
          if (aiState == AiEngineState.missingModel) ...[
            UiCard(
              onTap: () => context.go('/settings'),
              child: Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    color: context.uiColors.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Offline AI Model Available',
                          style: context.uiText.bodyStrong,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap to initialize local AI for instant summaries and smart captures.',
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
            const SizedBox(height: 12),
          ],

          // 3. Error Banner
          if (firstError != null) ...[
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
            ),
            const SizedBox(height: 12),
          ],

          if (isLoading)
            const _TodaySkeleton()
          else ...[
            // 4. Daily Vitals & Momentum Metric Strip
            _VitalsMetricsGrid(
              tasks: tasksAsync.value ?? const [],
              habits: habitsAsync.value ?? const [],
              dueCardsCount: dueCardsAsync.value?.length ?? 0,
              focusHistory: focusHistory,
              activeSession: activeFocusSession,
              selectedDay: selectedDay,
              ref: ref,
            ),
            const SizedBox(height: 14),

            // 5. Active Focus Live Card OR Quick Start Focus Launcher
            _HomeFocusSection(
              settings: settings,
              activeSession: activeFocusSession,
            ),
            const SizedBox(height: 14),

            // 6. Flashcard Mastery Due Banner (if cards need review)
            if ((dueCardsAsync.value?.length ?? 0) > 0) ...[
              _DueFlashcardsBanner(
                dueCount: dueCardsAsync.value!.length,
                decksCount: decksAsync.value?.length ?? 0,
              ),
              const SizedBox(height: 14),
            ],

            // 7. Today's Agenda & Action Stream
            _TodayAgendaSection(
              selectedDay: selectedDay,
              tasks: tasksAsync.value ?? const [],
              habits: habitsAsync.value ?? const [],
              routines: routinesAsync.value ?? const [],
              events: eventsAsync.value ?? const [],
              sessionDone: sessionDone,
              ref: ref,
            ),
            const SizedBox(height: 24),

            // 8. Academics, Goals & Daily Insights Cards
            _AcademicsAndGoalsSection(
              courses: coursesAsync.value ?? const [],
              goals: goalsAsync.value ?? const [],
            ),
            const SizedBox(height: 24),

            // 9. Recent Notes & Daily Journal Quick Capture Row
            _RecentNotesAndJournalSection(
              notes: notesAsync.value ?? const [],
              journal: journalAsync.value ?? const [],
            ),
            const SizedBox(height: 28),
          ],
        ],
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// 1. 7-Day Date Strip
/// ----------------------------------------------------------------------------
class _DateStrip extends StatefulWidget {
  const _DateStrip({required this.selected, required this.onSelect});

  final DateTime selected;
  final ValueChanged<DateTime> onSelect;

  @override
  State<_DateStrip> createState() => _DateStripState();
}

class _DateStripState extends State<_DateStrip> {
  late final ScrollController _scrollCtrl;
  late final List<DateTime> _days;
  static const double _itemWidth = 52.0;
  static const double _itemMargin = 3.0;
  static const double _totalItemWidth = _itemWidth + (_itemMargin * 2);

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    // 35 days: past 7 days, today, next 27 days (full month horizon)
    _days = List.generate(
      35,
      (i) => today.subtract(const Duration(days: 7)).add(Duration(days: i)),
    );

    _scrollCtrl = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToSelected(animate: false));
  }

  @override
  void didUpdateWidget(covariant _DateStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) {
      _scrollToSelected(animate: true);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToSelected({bool animate = true}) {
    if (!_scrollCtrl.hasClients) return;
    final index = _days.indexWhere((d) => d == widget.selected);
    if (index == -1) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final targetOffset = (index * _totalItemWidth) - (screenWidth / 2) + (_totalItemWidth / 2);
    final clampedOffset = targetOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent);

    if (animate) {
      _scrollCtrl.animateTo(
        clampedOffset,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _scrollCtrl.jumpTo(clampedOffset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());

    return SizedBox(
      height: 68,
      child: ListView.builder(
        controller: _scrollCtrl,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _days.length,
        itemBuilder: (context, index) {
          final d = _days[index];
          final isSelected = d == widget.selected;
          final isToday = d == today;

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onSelect(d);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: _itemWidth,
              margin: const EdgeInsets.symmetric(horizontal: _itemMargin),
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
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected
                          ? context.uiColors.onPrimary.withValues(alpha: 0.8)
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
          );
        },
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// 2. Vital Metrics Overview Grid
/// ----------------------------------------------------------------------------
class _VitalsMetricsGrid extends StatelessWidget {
  const _VitalsMetricsGrid({
    required this.tasks,
    required this.habits,
    required this.dueCardsCount,
    required this.focusHistory,
    this.activeSession,
    required this.selectedDay,
    required this.ref,
  });

  final List<Task> tasks;
  final List<Habit> habits;
  final int dueCardsCount;
  final List<FocusSession> focusHistory;
  final FocusSession? activeSession;
  final DateTime selectedDay;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final isToday = _dateOnly(DateTime.now()) == selectedDay;

    // Tasks for selected day
    final dayTasks = tasks.where((t) {
      final due = t.dueDate == null ? null : _dateOnly(t.dueDate!);
      return due == selectedDay || (due == null && isToday);
    }).toList();
    final totalTasks = dayTasks.length;
    final doneTasks = dayTasks.where((t) => t.isCompleted).length;

    // Habits done today
    int doneHabits = 0;
    for (final h in habits) {
      final entries = ref.watch(habitEntriesStreamProvider(h.id)).value ?? const [];
      final done = entries.any((e) => e.isDone && _dateOnly(e.date) == selectedDay);
      if (done) doneHabits++;
    }
    final totalHabits = habits.length;

    // Total focus minutes today calculated with cycles & active session
    final todayFocusMinutes = computeTotalFocusMinutes(
      focusHistory,
      activeSession: activeSession,
      forDay: selectedDay,
    );

    final String focusDisplay;
    if (todayFocusMinutes >= 60) {
      final h = todayFocusMinutes ~/ 60;
      final m = todayFocusMinutes % 60;
      focusDisplay = m > 0 ? '${h}h ${m}m' : '${h}h';
    } else {
      focusDisplay = '${todayFocusMinutes}m';
    }

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.checklist_rounded,
            color: const Color(0xFF10B981),
            value: totalTasks == 0 ? '0' : '$doneTasks/$totalTasks',
            label: 'Tasks',
            onTap: () => context.push('/todos'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            icon: Icons.repeat_rounded,
            color: const Color(0xFF3B82F6),
            value: totalHabits == 0 ? '0' : '$doneHabits/$totalHabits',
            label: 'Habits',
            onTap: () => context.push('/habits'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            icon: Icons.style_outlined,
            color: const Color(0xFFEC4899),
            value: '$dueCardsCount',
            label: 'Due Cards',
            onTap: () => context.push('/flashcards'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _MetricCard(
            icon: Icons.timer_outlined,
            color: const Color(0xFF8B5CF6),
            value: focusDisplay,
            label: 'Focus',
            onTap: () => FocusHistoryScreen.show(context),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: context.uiColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.uiColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: context.uiText.bodyStrong.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: context.uiText.caption.copyWith(
                fontSize: 10,
                color: context.uiColors.foregroundMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// 3. Focus Section (Active Live Session OR Quick Start Preset Launcher)
/// ----------------------------------------------------------------------------
class _HomeFocusSection extends ConsumerStatefulWidget {
  const _HomeFocusSection({
    required this.settings,
    required this.activeSession,
  });

  final AppSettings settings;
  final FocusSession? activeSession;

  @override
  ConsumerState<_HomeFocusSection> createState() => _HomeFocusSectionState();
}

class _HomeFocusSectionState extends ConsumerState<_HomeFocusSection> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _checkTicker();
  }

  @override
  void didUpdateWidget(covariant _HomeFocusSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkTicker();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _checkTicker() {
    final focusEnd = widget.settings.focusSessionEndsAt;
    final isFocusActive = focusEnd != null && focusEnd.isAfter(DateTime.now());

    if (isFocusActive) {
      if (_ticker == null || !_ticker!.isActive) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final focusEnd = widget.settings.focusSessionEndsAt;
    final now = DateTime.now();
    final isFocusActive = focusEnd != null && focusEnd.isAfter(now);

    if (isFocusActive) {
      final totalSeconds = focusEnd.difference(now).inSeconds.clamp(0, 24 * 60 * 60);
      final minutes = totalSeconds ~/ 60;
      final seconds = totalSeconds % 60;
      final isBreak = widget.settings.focusSessionPhase == 'break';
      final accentColor = isBreak ? const Color(0xFFF59E0B) : const Color(0xFF6366F1);

      final effectiveStart = widget.settings.focusSessionStartedAt ??
          widget.activeSession?.startedAt ??
          focusEnd.subtract(Duration(seconds: totalSeconds > 0 ? totalSeconds : 25 * 60));
      final sessionTotalSec = focusEnd.difference(effectiveStart).inSeconds;
      final elapsedSec = now.difference(effectiveStart).inSeconds;
      final progress = sessionTotalSec > 0
          ? (elapsedSec / sessionTotalSec).clamp(0.0, 1.0)
          : 0.0;

      return UiCard(
        accentColor: accentColor,
        onTap: () {
          ZenFocusScreen.open(
            context,
            ref,
            end: focusEnd,
            startedAt: widget.settings.focusSessionStartedAt ?? widget.activeSession?.startedAt,
            presetLabel: focusPresetFromId(widget.activeSession?.presetId)?.chipLabel,
          );
        },
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: accentColor.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
                Icon(
                  isBreak ? Icons.local_cafe_outlined : Icons.timer_outlined,
                  color: accentColor,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isBreak ? 'Rest & Recharge' : 'Deep Focus Active',
                        style: context.uiText.bodyStrong,
                      ),
                      const SizedBox(width: 6),
                      UiBadge(
                        label: isBreak ? 'Break' : 'Focusing',
                        intent: isBreak ? UiIntent.warning : UiIntent.primary,
                        size: UiSize.xs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')} remaining · Tap for Zen Mode',
                    style: context.uiText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: accentColor,
                    ),
                  ),
                ],
              ),
            ),
            if (isBreak)
              UiIconButton(
                icon: Icons.play_arrow_rounded,
                tooltip: 'Resume Focus & Skip Break',
                onPressed: () =>
                    FocusTimerService().skipBreakAndStartWork(ref, context: context),
              ),
            UiIconButton(
              icon: Icons.fullscreen_outlined,
              tooltip: 'Zen Full Screen',
              onPressed: () {
                ZenFocusScreen.open(
                  context,
                  ref,
                  end: focusEnd,
                  startedAt: widget.settings.focusSessionStartedAt ?? widget.activeSession?.startedAt,
                  presetLabel: focusPresetFromId(widget.activeSession?.presetId)?.chipLabel,
                );
              },
            ),
          ],
        ),
      );
    }

    // Idle State: 1-Tap Quick Start Chips
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 16, color: context.uiColors.primary),
            const SizedBox(width: 6),
            Text('Quick Focus Sprint', style: context.uiText.bodyStrong),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/clock'),
              child: const Text('Open Clock'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: _FocusPresetQuickButton(
                label: 'Pomodoro',
                duration: '25m',
                icon: Icons.timer_outlined,
                accentColor: const Color(0xFF818CF8),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final end = DateTime.now().add(const Duration(minutes: 25));
                  await FocusTimerService().startSession(
                    ref,
                    workMinutes: 25,
                    breakMinutes: 5,
                    preset: FocusPreset.pomodoro,
                  );
                  if (context.mounted) {
                    ZenFocusScreen.open(
                      context,
                      ref,
                      end: end,
                      startedAt: DateTime.now(),
                      presetLabel: FocusPreset.pomodoro.chipLabel,
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FocusPresetQuickButton(
                label: 'Deep Work',
                duration: '50m',
                icon: Icons.laptop_mac_outlined,
                accentColor: const Color(0xFF38BDF8),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final end = DateTime.now().add(const Duration(minutes: 50));
                  await FocusTimerService().startSession(
                    ref,
                    workMinutes: 50,
                    breakMinutes: 10,
                    preset: FocusPreset.deepWork,
                  );
                  if (context.mounted) {
                    ZenFocusScreen.open(
                      context,
                      ref,
                      end: end,
                      startedAt: DateTime.now(),
                      presetLabel: FocusPreset.deepWork.chipLabel,
                    );
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FocusPresetQuickButton(
                label: 'Flow State',
                duration: '90m',
                icon: Icons.waves_outlined,
                accentColor: const Color(0xFFFBBF24),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  final end = DateTime.now().add(const Duration(minutes: 90));
                  await FocusTimerService().startSession(
                    ref,
                    workMinutes: 90,
                    breakMinutes: 20,
                    preset: FocusPreset.flowState,
                  );
                  if (context.mounted) {
                    ZenFocusScreen.open(
                      context,
                      ref,
                      end: end,
                      startedAt: DateTime.now(),
                      presetLabel: FocusPreset.flowState.chipLabel,
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _FocusPresetQuickButton extends StatelessWidget {
  const _FocusPresetQuickButton({
    required this.label,
    required this.duration,
    required this.icon,
    this.accentColor,
    required this.onTap,
  });

  final String label;
  final String duration;
  final IconData icon;
  final Color? accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? context.uiColors.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: context.uiColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.uiColors.border),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  duration,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: context.uiColors.foregroundMuted,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// 4. Flashcards Due Review Banner
/// ----------------------------------------------------------------------------
class _DueFlashcardsBanner extends StatelessWidget {
  const _DueFlashcardsBanner({
    required this.dueCount,
    required this.decksCount,
  });

  final int dueCount;
  final int decksCount;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/flashcards'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF6366F1).withValues(alpha: 0.15),
              const Color(0xFF8B5CF6).withValues(alpha: 0.08),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.psychology_outlined,
                color: Color(0xFF818CF8),
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$dueCount flashcards due for review',
                    style: context.uiText.bodyStrong,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Spaced repetition memory review across $decksCount decks',
                    style: context.uiText.caption.copyWith(
                      color: context.uiColors.foregroundMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            UiButton(
              label: 'Review',
              variant: UiVariant.primary,
              size: UiSize.xs,
              leadingIcon: Icons.play_arrow_rounded,
              onPressed: () => context.push('/flashcards'),
            ),
          ],
        ),
      ),
    );
  }
}

/// ----------------------------------------------------------------------------
/// 5. Today Agenda Section (Tasks, Habits, Routines, Calendar)
/// ----------------------------------------------------------------------------
class _TodayAgendaSection extends ConsumerWidget {
  const _TodayAgendaSection({
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
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(homeAgendaFilterProvider);
    final items = <_TodayItem>[];

    // Calendar events
    if (filter == 'all' || filter == 'events') {
      for (final e in events) {
        final start = _dateOnly(e.startTime);
        if (start != selectedDay) continue;
        if (e.id.startsWith('habit:') ||
            e.id.startsWith('task:') ||
            e.id.startsWith('goal:') ||
            e.category == 'Habit' ||
            e.category == 'Task' ||
            e.category == 'Goal') {
          continue;
        }
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
            tag: 'Event',
          ),
        );
      }
    }

    // Tasks
    if (filter == 'all' || filter == 'tasks') {
      for (final t in tasks) {
        final due = t.dueDate == null ? null : _dateOnly(t.dueDate!);
        final belongsHere = due == selectedDay || (due == null && _isToday);
        if (!belongsHere) continue;
        items.add(
          _TodayItem(
            kind: _TodayKind.task,
            id: t.id,
            title: t.title,
            subtitle: t.subtitle.isNotEmpty ? t.subtitle : null,
            timeLabel: due != null ? DateFormat.jm().format(t.dueDate!) : null,
            done: t.isCompleted,
            tag: 'Task',
            onToggle: () => ref
                .read(taskRepositoryProvider)
                .toggleTaskCompletion(t.id, t.isCompleted),
          ),
        );
      }
    }

    // Habits
    if (filter == 'all' || filter == 'habits') {
      for (final h in habits) {
        final entries = ref.watch(habitEntriesStreamProvider(h.id)).value ?? const [];
        final done = entries.any((e) => e.isDone && _dateOnly(e.date) == selectedDay);
        items.add(
          _TodayItem(
            kind: _TodayKind.habit,
            id: h.id,
            title: h.title,
            subtitle: h.streak > 0 ? '${h.streak} day streak' : 'Daily habit',
            done: done,
            tag: h.category ?? 'Habit',
            onToggle: () =>
                ref.read(habitRepositoryProvider).toggleEntry(h.id, selectedDay),
          ),
        );
      }
    }

    // Routines
    if (filter == 'all' || filter == 'routines') {
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
            tag: 'Routine',
            onToggle: () {
              final notifier = ref.read(_sessionDoneProvider.notifier);
              final next = {...notifier.state};
              done ? next.remove(key) : next.add(key);
              notifier.state = next;
            },
          ),
        );
      }
    }

    // Sorting: timed items first
    items.sort((a, b) {
      if (a.timeLabel != null && b.timeLabel == null) return -1;
      if (a.timeLabel == null && b.timeLabel != null) return 1;
      if (a.timeLabel != null && b.timeLabel != null) {
        return a.timeLabel!.compareTo(b.timeLabel!);
      }
      return a.kind.index.compareTo(b.kind.index);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Today\'s Agenda', style: context.uiText.bodyStrong),
            const Spacer(),
            UiIconButton(
              icon: Icons.add_circle_outline_rounded,
              tooltip: 'Add new task',
              onPressed: () => context.push('/todos/new'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Filter Pills
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _AgendaFilterChip(
                label: 'All Items',
                selected: filter == 'all',
                onTap: () =>
                    ref.read(homeAgendaFilterProvider.notifier).state = 'all',
              ),
              const SizedBox(width: 6),
              _AgendaFilterChip(
                label: 'Tasks',
                selected: filter == 'tasks',
                onTap: () =>
                    ref.read(homeAgendaFilterProvider.notifier).state = 'tasks',
              ),
              const SizedBox(width: 6),
              _AgendaFilterChip(
                label: 'Habits',
                selected: filter == 'habits',
                onTap: () =>
                    ref.read(homeAgendaFilterProvider.notifier).state = 'habits',
              ),
              const SizedBox(width: 6),
              _AgendaFilterChip(
                label: 'Routines',
                selected: filter == 'routines',
                onTap: () =>
                    ref.read(homeAgendaFilterProvider.notifier).state = 'routines',
              ),
              const SizedBox(width: 6),
              _AgendaFilterChip(
                label: 'Schedule',
                selected: filter == 'events',
                onTap: () =>
                    ref.read(homeAgendaFilterProvider.notifier).state = 'events',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        if (items.isEmpty)
          const UiEmptyState(
            compact: true,
            title: 'No agenda items',
            message: 'Nothing scheduled for this filter. Enjoy your day!',
            icon: Icons.wb_sunny_outlined,
          )
        else
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _TodayRow(item: item),
            ),
          ),
      ],
    );
  }
}

class _AgendaFilterChip extends StatelessWidget {
  const _AgendaFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? context.uiColors.primary : context.uiColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? context.uiColors.primary : context.uiColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? context.uiColors.onPrimary
                : context.uiColors.foreground,
          ),
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  const _TodayRow({required this.item});

  final _TodayItem item;

  IconData get _icon => switch (item.kind) {
        _TodayKind.task => Icons.checklist_rounded,
        _TodayKind.habit => Icons.repeat_rounded,
        _TodayKind.routine => Icons.wb_sunny_outlined,
        _TodayKind.event => Icons.calendar_today_outlined,
      };

  Color _tint(BuildContext context) => switch (item.kind) {
        _TodayKind.task => const Color(0xFF10B981),
        _TodayKind.habit => const Color(0xFF3B82F6),
        _TodayKind.routine => const Color(0xFFF59E0B),
        _TodayKind.event => const Color(0xFF8B5CF6),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final Color tint = item.color ?? _tint(context);
    final bool checkable = item.kind != _TodayKind.event;

    return UiCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_icon, size: 18, color: tint),
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
              onTap: () {
                HapticFeedback.lightImpact();
                item.onToggle();
              },
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

/// ----------------------------------------------------------------------------
/// 6. Academics & Goals Section
/// ----------------------------------------------------------------------------
class _AcademicsAndGoalsSection extends StatelessWidget {
  const _AcademicsAndGoalsSection({
    required this.courses,
    required this.goals,
  });

  final List<Course> courses;
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final topGoal = goals.isNotEmpty ? goals.first : null;
    final topCourse = courses.isNotEmpty ? courses.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Academics & Goals', style: context.uiText.bodyStrong),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/courses'),
              child: const Text('View Courses'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Course Card
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/courses'),
                child: UiCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.school_outlined,
                              size: 16, color: Color(0xFF6366F1)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Academics',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.uiColors.foregroundMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        topCourse != null ? topCourse.name : 'No courses enrolled',
                        style: context.uiText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topCourse != null
                            ? '${topCourse.code ?? "Subject"} · ${topCourse.room ?? ""}'
                            : 'Tap to add your study schedule',
                        style: context.uiText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Top Goal Card
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/goals'),
                child: UiCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.flag_outlined,
                              size: 16, color: Color(0xFF10B981)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Key Milestone',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: context.uiColors.foregroundMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        topGoal != null ? topGoal.title : 'Set a new goal',
                        style: context.uiText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        topGoal != null
                            ? '${topGoal.progressPercent}% progress completed'
                            : 'Track milestones & targets',
                        style: context.uiText.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ----------------------------------------------------------------------------
/// 7. Notes & Journal Quick Capture Section
/// ----------------------------------------------------------------------------
class _RecentNotesAndJournalSection extends StatelessWidget {
  const _RecentNotesAndJournalSection({
    required this.notes,
    required this.journal,
  });

  final List<Note> notes;
  final List<JournalData> journal;

  @override
  Widget build(BuildContext context) {
    final recentNote = notes.isNotEmpty ? notes.first : null;
    final recentJournal = journal.isNotEmpty ? journal.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Knowledge & Reflection', style: context.uiText.bodyStrong),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/notes'),
              child: const Text('All Notes'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // Notes Card
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (recentNote != null) {
                    context.push('/notes/${recentNote.id}');
                  } else {
                    context.push('/notes/new');
                  }
                },
                child: UiCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.edit_note_rounded,
                              size: 18, color: Color(0xFF3B82F6)),
                          const SizedBox(width: 6),
                          Text(
                            'Latest Note',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.uiColors.foregroundMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recentNote != null && recentNote.title.isNotEmpty
                            ? recentNote.title
                            : 'Write a new note',
                        style: context.uiText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recentNote != null
                            ? DateFormat.yMMMd().format(recentNote.createdAt)
                            : 'Capture ideas & study notes',
                        style: context.uiText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // Journal Card
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  if (recentJournal != null) {
                    context.push('/journal/${recentJournal.id}');
                  } else {
                    context.push('/journal/new');
                  }
                },
                child: UiCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.menu_book_outlined,
                              size: 16, color: Color(0xFFF59E0B)),
                          const SizedBox(width: 6),
                          Text(
                            'Daily Journal',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: context.uiColors.foregroundMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recentJournal != null && recentJournal.title.isNotEmpty
                            ? recentJournal.title
                            : 'Check-in reflection',
                        style: context.uiText.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        recentJournal != null
                            ? DateFormat.yMMMd().format(recentJournal.createdAt)
                            : 'Reflect on today\'s wins',
                        style: context.uiText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// ----------------------------------------------------------------------------
/// Skeleton Loader
/// ----------------------------------------------------------------------------
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
