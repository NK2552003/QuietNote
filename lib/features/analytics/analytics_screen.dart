import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/goals/goal_editor_screen.dart' show goalCategoryColor;
import 'package:quietnote/features/habits/habit_editor_screen.dart' show habitCategoryColor, habitCategoryIcon;
import 'package:quietnote/features/routines/routines_screen.dart' show RoutineContent;

/// Selected lookback window (days) driving every rate/consistency figure
/// on the screen. Persisted only for the lifetime of this screen instance.
final _rangeDaysProvider = StateProvider<int>((ref) => 30);

String _rangeLabel(int days) {
  if (days == 7) return 'Last 7 days';
  if (days == 90) return 'Last 90 days';
  return 'Last 30 days';
}

String _taskPriorityLabel(int p) => switch (p) {
      3 => 'High',
      2 => 'Medium',
      1 => 'Low',
      _ => 'None',
    };

Color _taskPriorityColor(BuildContext context, int priority) {
  final c = context.uiColors;
  switch (priority) {
    case 3:
      return c.destructive;
    case 2:
      return c.warning;
    case 1:
      return c.info;
    default:
      return c.foregroundMuted;
  }
}

/// How many of a habit's scheduled days fall inside the trailing [days]
/// window (used to decide whether a habit has enough data to be ranked).
int _scheduledCountInWindow(Habit habit, int days) {
  final today = dateOnly(DateTime.now());
  var n = 0;
  for (var i = 0; i < days; i++) {
    if (isHabitScheduled(habit, today.subtract(Duration(days: i)))) n++;
  }
  return n;
}

/// Completion rate (0..1) over a trailing [days]-day window, optionally
/// shifted back by [offset] days — used to compare the current period
/// against the equivalent prior period for a trend delta.
double _completionRateWindow(Habit habit, Set<DateTime> doneDays, {required int days, int offset = 0}) {
  final today = dateOnly(DateTime.now());
  var scheduled = 0;
  var done = 0;
  for (var i = offset; i < offset + days; i++) {
    final d = today.subtract(Duration(days: i));
    if (!isHabitScheduled(habit, d)) continue;
    scheduled++;
    if (doneDays.contains(d)) done++;
  }
  return scheduled == 0 ? 0 : done / scheduled;
}

class _Insight {
  const _Insight({required this.title, required this.message, required this.intent, required this.icon});
  final String title;
  final String message;
  final UiIntent intent;
  final IconData icon;
}

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Task>[]);
    final habits = ref.watch(habitsStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Habit>[]);
    final goals = ref.watch(goalsStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Goal>[]);
    final courses = ref.watch(coursesStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Course>[]);
    final allAssessments = ref.watch(allAssessmentsStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Assessment>[]);
    final journal = ref.watch(journalStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <JournalData>[]);
    final notes = ref.watch(notesStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Note>[]);
    final routines = ref.watch(routinesStreamProvider).maybeWhen(data: (d) => d, orElse: () => const <Routine>[]);
    final rangeDays = ref.watch(_rangeDaysProvider);

    // Entry logs for every habit, keyed by habit id, so every section below
    // can compute streaks/consistency without re-querying the database.
    final Map<String, Set<DateTime>> doneDaysByHabit = <String, Set<DateTime>>{
      for (final h in habits)
        h.id: (ref.watch(habitEntriesStreamProvider(h.id)).maybeWhen(data: (d) => d, orElse: () => const <HabitEntry>[]))
            .where((e) => e.isDone)
            .map((e) => dateOnly(e.date))
            .toSet(),
    };

    final hasAnyData =
        tasks.isNotEmpty || habits.isNotEmpty || goals.isNotEmpty || journal.isNotEmpty || notes.isNotEmpty || routines.isNotEmpty || courses.isNotEmpty;

    // Build the page content inside a try/catch so a synchronous build error
    // doesn't leave the whole page blank — show a friendly error instead.
    Widget pageChild;
    try {
      pageChild = !hasAnyData
          ? const Padding(
              padding: EdgeInsets.only(top: 48),
              child: UiEmptyState(
                title: 'Nothing to analyze yet',
                message: 'Start logging habits, tasks, goals or journal entries and your insights will show up here.',
                icon: Icons.insights_outlined,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: UiToggleGroup<int>(
                    expand: true,
                    variant: UiToggleGroupVariant.segmented,
                    orientation: UiOrientation.horizontal,
                    size: UiSize.sm,
                    value: rangeDays,
                    onChanged: (v) => ref.read(_rangeDaysProvider.notifier).state = v,
                    options: const [
                      UiToggleOption(value: 7, label: '7D'),
                      UiToggleOption(value: 30, label: '30D'),
                      UiToggleOption(value: 90, label: '90D'),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SectionHeader(title: 'Overview', subtitle: _rangeLabel(rangeDays)),
                const SizedBox(height: 12),
                _OverviewGrid(
                  tasks: tasks,
                  habits: habits,
                  goals: goals,
                  journal: journal,
                  doneDaysByHabit: doneDaysByHabit,
                  rangeDays: rangeDays,
                ),
                _InsightsSection(
                  tasks: tasks,
                  habits: habits,
                  goals: goals,
                  journal: journal,
                  doneDaysByHabit: doneDaysByHabit,
                  rangeDays: rangeDays,
                ),
                const SizedBox(height: 8),
                _ActivityTrendSection(habits: habits, journal: journal, notes: notes, doneDaysByHabit: doneDaysByHabit),
                const SizedBox(height: 28),
                if (habits.isNotEmpty) ...[
                  _HabitsSection(habits: habits, doneDaysByHabit: doneDaysByHabit, rangeDays: rangeDays),
                  const SizedBox(height: 28),
                ],
                if (goals.isNotEmpty) ...[
                  _GoalsSection(goals: goals),
                  const SizedBox(height: 28),
                ],
                if (courses.isNotEmpty) ...[
                  _AcademicsSection(courses: courses, allAssessments: allAssessments),
                  const SizedBox(height: 28),
                ],
                if (tasks.isNotEmpty) ...[
                  _TasksSection(tasks: tasks),
                  const SizedBox(height: 28),
                ],
                if (journal.isNotEmpty || notes.isNotEmpty) ...[
                  _JournalNotesSection(journal: journal, notes: notes),
                  const SizedBox(height: 28),
                ],
                if (routines.isNotEmpty) _RoutinesSection(routines: routines),
              ],
            );
    } catch (e, st) {
      debugPrint('Analytics build error: $e\n$st');
      pageChild = Padding(
        padding: const EdgeInsets.only(top: 48),
        child: UiCallout(
          title: 'Error rendering analytics',
          message: 'Something went wrong while building analytics.\n${e.toString()}',
          intent: UiIntent.danger,
          icon: Icons.error_outline_rounded,
        ),
      );
    }

    return UiPage(
      header: const UiHeader(
        title: 'Analytics',
        subtitle: 'Patterns across everything you track.',
      ),
      child: pageChild,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle, this.action});
  final String title;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.uiText.title),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted)),
              ],
            ],
          ),
        ),
        if (action != null) action!,
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: context.uiText.heading.copyWith(color: valueColor), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({
    required this.tasks,
    required this.habits,
    required this.goals,
    required this.journal,
    required this.doneDaysByHabit,
    required this.rangeDays,
  });

  final List<Task> tasks;
  final List<Habit> habits;
  final List<Goal> goals;
  final List<JournalData> journal;
  final Map<String, Set<DateTime>> doneDaysByHabit;
  final int rangeDays;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final today = dateOnly(DateTime.now());

    final completedTasks = tasks.where((t) => t.isCompleted).length;

    final activeHabits = habits.where((h) => !h.archived).toList();
    var curSum = 0.0;
    var prevSum = 0.0;
    var counted = 0;
    for (final h in activeHabits) {
      final done = doneDaysByHabit[h.id] ?? const <DateTime>{};
      curSum += _completionRateWindow(h, done, days: rangeDays);
      prevSum += _completionRateWindow(h, done, days: rangeDays, offset: rangeDays);
      counted++;
    }
    final curRate = counted == 0 ? 0.0 : curSum / counted;
    final prevRate = counted == 0 ? 0.0 : prevSum / counted;
    final rateDeltaPts = counted == 0 ? null : ((curRate - prevRate) * 100).round();

    final avgGoalProgress = goals.isEmpty ? 0 : goals.map((g) => g.progressPercent).reduce((a, b) => a + b) / goals.length;

    final journalDays = journal.map((j) => dateOnly(j.createdAt)).toSet();
    var journalStreak = 0;
    var streakCursor = today;
    while (journalDays.contains(streakCursor)) {
      journalStreak++;
      streakCursor = streakCursor.subtract(const Duration(days: 1));
    }

    final last14 = List<DateTime>.generate(14, (i) => today.subtract(Duration(days: 13 - i)));
    final habitSpark = last14.map((d) {
      final scheduled = activeHabits.where((h) => isHabitScheduled(h, d)).toList();
      if (scheduled.isEmpty) return 0.0;
      final done = scheduled.where((h) => (doneDaysByHabit[h.id] ?? const <DateTime>{}).contains(d)).length;
      return done / scheduled.length;
    }).toList();
    final journalSpark = last14.map((d) => journalDays.contains(d) ? 1.0 : 0.0).toList();

    final tasksCard = UiMetricCard(
      label: 'Tasks done',
      value: '$completedTasks/${tasks.length}',
      icon: Icons.check_circle_outline_rounded,
    );
    final habitsCard = UiMetricCard(
      label: 'Habit consistency',
      value: '${(curRate * 100).round()}%',
      delta: rateDeltaPts,
      icon: Icons.repeat_rounded,
      chart: activeHabits.isEmpty ? null : UiSparkChart(values: habitSpark, color: c.primary),
    );
    final goalsCard = UiMetricCard(
      label: 'Avg goal progress',
      value: '${avgGoalProgress.round()}%',
      icon: Icons.flag_outlined,
    );
    final journalCard = UiMetricCard(
      label: 'Journal streak',
      value: journalStreak == 0 ? '0 days' : '$journalStreak day${journalStreak == 1 ? '' : 's'}',
      icon: Icons.menu_book_outlined,
      chart: journal.isEmpty ? null : UiSparkChart(values: journalSpark, color: c.info),
    );

    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tasksCard,
                  const SizedBox(height: 12),
                  habitsCard,
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  goalsCard,
                  const SizedBox(height: 12),
                  journalCard,
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InsightsSection extends StatelessWidget {
  const _InsightsSection({
    required this.tasks,
    required this.habits,
    required this.goals,
    required this.journal,
    required this.doneDaysByHabit,
    required this.rangeDays,
  });

  final List<Task> tasks;
  final List<Habit> habits;
  final List<Goal> goals;
  final List<JournalData> journal;
  final Map<String, Set<DateTime>> doneDaysByHabit;
  final int rangeDays;

  List<_Insight> _build() {
    final insights = <_Insight>[];
    final today = dateOnly(DateTime.now());

    final overdueTasks = tasks.where((t) => !t.isCompleted && t.dueDate != null && dateOnly(t.dueDate!).isBefore(today)).length;
    if (overdueTasks > 0) {
      insights.add(_Insight(
        title: '$overdueTasks task${overdueTasks == 1 ? '' : 's'} overdue',
        message: "Clear these first \u2014 they're dragging your completion rate down.",
        intent: UiIntent.danger,
        icon: Icons.error_outline_rounded,
      ));
    }

    final soonGoals = goals
        .where((g) =>
            g.progressPercent < 100 &&
            g.deadline != null &&
            !dateOnly(g.deadline!).isBefore(today) &&
            dateOnly(g.deadline!).difference(today).inDays <= 7)
        .toList()
      ..sort((a, b) => a.deadline!.compareTo(b.deadline!));
    if (soonGoals.isNotEmpty) {
      final g = soonGoals.first;
      final days = dateOnly(g.deadline!).difference(today).inDays;
      insights.add(_Insight(
        title: '"${g.title}" is due ${days == 0 ? 'today' : 'in $days day${days == 1 ? '' : 's'}'}',
        message: 'Currently at ${g.progressPercent}% progress.',
        intent: UiIntent.warning,
        icon: Icons.flag_outlined,
      ));
    }

    final active = habits.where((h) => !h.archived).toList();
    MapEntry<Habit, double>? best;
    MapEntry<Habit, double>? worst;
    for (final h in active) {
      if (_scheduledCountInWindow(h, rangeDays) == 0) continue;
      final done = doneDaysByHabit[h.id] ?? const <DateTime>{};
      final rate = _completionRateWindow(h, done, days: rangeDays);
      if (best == null) {
        best = MapEntry(h, rate);
      } else if (rate > best.value) {
        best = MapEntry(h, rate);
      }
      if (worst == null) {
        worst = MapEntry(h, rate);
      } else if (rate < worst.value) {
        worst = MapEntry(h, rate);
      }
    }
    if (best != null && best.value >= 0.7) {
      insights.add(_Insight(
        title: '${best.key.title} is on a roll',
        message: '${(best.value * 100).round()}% consistency over ${_rangeLabel(rangeDays).toLowerCase()}.',
        intent: UiIntent.success,
        icon: Icons.local_fire_department_rounded,
      ));
    }
    if (worst != null && worst.value < 0.4 && worst.key.id != best?.key.id) {
      insights.add(_Insight(
        title: '${worst.key.title} needs attention',
        message: 'Only ${(worst.value * 100).round()}% consistency over ${_rangeLabel(rangeDays).toLowerCase()}.',
        intent: UiIntent.warning,
        icon: Icons.trending_down_rounded,
      ));
    }

    if (journal.isNotEmpty) {
      final entryDays = journal.map((j) => dateOnly(j.createdAt)).toSet();
      var streak = 0;
      var cursor = today;
      while (entryDays.contains(cursor)) {
        streak++;
        cursor = cursor.subtract(const Duration(days: 1));
      }
      if (streak >= 3) {
        insights.add(_Insight(
          title: '$streak-day journaling streak',
          message: 'Keep the reflection habit going.',
          intent: UiIntent.info,
          icon: Icons.menu_book_outlined,
        ));
      }
    }

    return insights;
  }

  @override
  Widget build(BuildContext context) {
    final insights = _build().take(3).toList();
    if (insights.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in insights) ...[
            UiCallout(title: i.title, message: i.message, intent: i.intent, icon: i.icon),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _ActivityTrendSection extends StatelessWidget {
  const _ActivityTrendSection({
    required this.habits,
    required this.journal,
    required this.notes,
    required this.doneDaysByHabit,
  });

  final List<Habit> habits;
  final List<JournalData> journal;
  final List<Note> notes;
  final Map<String, Set<DateTime>> doneDaysByHabit;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    const windowDays = 14;
    final today = dateOnly(DateTime.now());
    final days = List<DateTime>.generate(windowDays, (i) => today.subtract(Duration(days: windowDays - 1 - i)));

    final points = days.map((d) {
      final habitCount = habits.where((h) => (doneDaysByHabit[h.id] ?? const <DateTime>{}).contains(d)).length;
      final journalCount = journal.where((j) => dateOnly(j.createdAt) == d).length;
      final noteCount = notes.where((n) => dateOnly(n.createdAt) == d).length;
      return UiChartPoint(
        label: DateFormat.E().format(d),
        values: [habitCount.toDouble(), journalCount.toDouble(), noteCount.toDouble()],
      );
    }).toList();

    final hasActivity = points.any((p) => p.values.any((v) => v > 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'Activity', subtitle: 'Habits, journal & notes over the last 14 days'),
        const SizedBox(height: 12),
        UiCard(
          padding: const EdgeInsets.all(16),
          child: hasActivity
              ? UiChart(
                  data: points,
                  series: [
                    UiChartSeries(name: 'Habits', color: c.series[0], type: UiChartSeriesType.bar),
                    UiChartSeries(name: 'Journal', color: c.series[1], type: UiChartSeriesType.bar),
                    UiChartSeries(name: 'Notes', color: c.series[2], type: UiChartSeriesType.bar),
                  ],
                  height: 200,
                  stacked: true,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No activity logged in the last two weeks yet.',
                      style: context.uiText.caption.copyWith(color: c.foregroundMuted),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _HabitsSection extends StatelessWidget {
  const _HabitsSection({required this.habits, required this.doneDaysByHabit, required this.rangeDays});
  final List<Habit> habits;
  final Map<String, Set<DateTime>> doneDaysByHabit;
  final int rangeDays;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final active = habits.where((h) => !h.archived).toList();
    final bestStreak = active.isEmpty ? 0 : active.map((h) => h.streak).reduce((a, b) => a > b ? a : b);

    final rated = <MapEntry<Habit, double>>[];
    for (final h in active) {
      if (_scheduledCountInWindow(h, rangeDays) == 0) continue;
      final done = doneDaysByHabit[h.id] ?? const <DateTime>{};
      rated.add(MapEntry(h, _completionRateWindow(h, done, days: rangeDays)));
    }
    rated.sort((a, b) => b.value.compareTo(a.value));
    final avgRate = rated.isEmpty ? 0.0 : rated.map((e) => e.value).reduce((a, b) => a + b) / rated.length;

    final byCategory = <String, int>{};
    for (final h in active) {
      final key = (h.category == null || h.category!.isEmpty) ? 'Other' : h.category!;
      byCategory[key] = (byCategory[key] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Habits',
          subtitle: '${active.length} active \u00b7 ${_rangeLabel(rangeDays)}',
          action: UiButton(label: 'View all', variant: UiVariant.link, size: UiSize.sm, onPressed: () => context.push('/habits')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatChip(label: 'Active', value: '${active.length}')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Best streak', value: '$bestStreak')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Avg consistency', value: '${(avgRate * 100).round()}%')),
          ],
        ),
        if (byCategory.length > 1) ...[
          const SizedBox(height: 12),
          UiCard(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: UiDonutChart(
                size: 150,
                slices: [
                  for (final entry in byCategory.entries)
                    UiDonutSlice(label: entry.key, value: entry.value.toDouble(), color: habitCategoryColor(context, entry.key)),
                ],
                center: Text('${active.length}\nhabits', textAlign: TextAlign.center, style: context.uiText.caption),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (rated.isEmpty)
          const UiEmptyState(title: 'No scheduled habits', message: 'Nothing was due in this period.', icon: Icons.repeat_rounded)
        else
          ...rated.take(5).map((e) {
            final h = e.key;
            final rate = e.value;
            final color = habitCategoryColor(context, h.category);
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: UiCard(
                onTap: () => context.push('/habits/${h.id}'),
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                      alignment: Alignment.center,
                      child: Icon(habitCategoryIcon(h.category), size: 18, color: color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h.title, style: context.uiText.bodyStrong, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 6),
                          UiProgressBar(
                            value: rate,
                            showValue: false,
                            intent: rate >= 0.7 ? UiIntent.success : (rate >= 0.4 ? UiIntent.warning : UiIntent.danger),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${(rate * 100).round()}%', style: context.uiText.bodyStrong),
                        if (h.streak > 0) ...[
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.local_fire_department_rounded, size: 12, color: c.foregroundMuted),
                              const SizedBox(width: 2),
                              Text('${h.streak}', style: context.uiText.caption),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

class _GoalsSection extends StatelessWidget {
  const _GoalsSection({required this.goals});
  final List<Goal> goals;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final completed = goals.where((g) => g.progressPercent >= 100).length;
    final overdue =
        goals.where((g) => g.progressPercent < 100 && g.deadline != null && dateOnly(g.deadline!).isBefore(today)).length;
    final onTrack = goals.length - completed - overdue;
    final avgProgress = goals.isEmpty ? 0 : goals.map((g) => g.progressPercent).reduce((a, b) => a + b) / goals.length;

    int score(Goal g) {
      if (g.progressPercent >= 100) return 2;
      if (g.deadline != null && dateOnly(g.deadline!).isBefore(today)) return 0;
      return 1;
    }

    final sorted = [...goals]..sort((a, b) {
        final sa = score(a);
        final sb = score(b);
        if (sa != sb) return sa.compareTo(sb);
        if (a.deadline != null && b.deadline != null) return a.deadline!.compareTo(b.deadline!);
        if (a.deadline != null) return -1;
        if (b.deadline != null) return 1;
        return b.progressPercent.compareTo(a.progressPercent);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Goals',
          subtitle: '${goals.length} total \u00b7 ${avgProgress.round()}% avg progress',
          action: UiButton(label: 'View all', variant: UiVariant.link, size: UiSize.sm, onPressed: () => context.push('/goals')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatChip(label: 'On track', value: '$onTrack')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Completed', value: '$completed')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Overdue', value: '$overdue')),
          ],
        ),
        const SizedBox(height: 12),
        ...sorted.take(5).map((g) {
          final color = goalCategoryColor(context, g.category);
          final isOverdue = g.progressPercent < 100 && g.deadline != null && dateOnly(g.deadline!).isBefore(today);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: UiCard(
              onTap: () => context.push('/goals/edit/${g.id}'),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(g.title, style: context.uiText.bodyStrong, overflow: TextOverflow.ellipsis)),
                      Text('${g.progressPercent}%', style: context.uiText.bodyStrong),
                    ],
                  ),
                  const SizedBox(height: 8),
                  UiProgressBar(
                    value: g.progressPercent / 100,
                    showValue: false,
                    intent: g.progressPercent >= 100 ? UiIntent.success : (isOverdue ? UiIntent.danger : UiIntent.primary),
                  ),
                  if (g.deadline != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      isOverdue ? 'Overdue \u00b7 ${DateFormat.yMMMd().format(g.deadline!)}' : 'Due ${DateFormat.yMMMd().format(g.deadline!)}',
                      style: context.uiText.caption.copyWith(color: isOverdue ? context.uiColors.destructive : context.uiColors.foregroundMuted),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

/// Overall academic standing: a simple mean of each course's weighted
/// average (documented choice — not weighted by assessment count, so a
/// course with few assessments doesn't get drowned out by one with many),
/// plus a per-course breakdown against each course's target grade.
class _AcademicsSection extends StatelessWidget {
  const _AcademicsSection({required this.courses, required this.allAssessments});
  final List<Course> courses;
  final List<Assessment> allAssessments;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final byCourse = <String, List<Assessment>>{
      for (final course in courses)
        course.id: allAssessments.where((a) => a.courseId == course.id).toList(),
    };
    final coursesWithData = courses.where((crs) => (byCourse[crs.id] ?? const []).isNotEmpty).toList();
    final perCourseAverage = <String, double>{
      for (final course in coursesWithData) course.id: weightedAverage(byCourse[course.id]!),
    };
    final overallAverage = perCourseAverage.isEmpty
        ? 0.0
        : perCourseAverage.values.reduce((a, b) => a + b) / perCourseAverage.length;
    final onTarget = coursesWithData.where((crs) {
      final target = crs.targetGrade;
      if (target == null) return false;
      return (perCourseAverage[crs.id] ?? 0) >= target;
    }).length;
    final withTarget = coursesWithData.where((crs) => crs.targetGrade != null).length;

    final sorted = [...coursesWithData]..sort((a, b) => (perCourseAverage[a.id] ?? 0).compareTo(perCourseAverage[b.id] ?? 0));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Academics',
          subtitle: '${courses.length} course${courses.length == 1 ? '' : 's'}',
          action: UiButton(label: 'View all', variant: UiVariant.link, size: UiSize.sm, onPressed: () => context.push('/courses')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Overall average',
                value: coursesWithData.isEmpty ? '\u2014' : '${overallAverage.toStringAsFixed(1)}%',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatChip(
                label: 'On target',
                value: withTarget == 0 ? '\u2014' : '$onTarget/$withTarget',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...sorted.take(5).map((course) {
          final average = perCourseAverage[course.id] ?? 0;
          final hasTarget = course.targetGrade != null;
          final meetsTarget = !hasTarget || average >= course.targetGrade!;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: UiCard(
              onTap: () => context.push('/courses/${course.id}'),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(course.name, style: context.uiText.bodyStrong, overflow: TextOverflow.ellipsis)),
                      Text('${average.toStringAsFixed(1)}%', style: context.uiText.bodyStrong),
                    ],
                  ),
                  const SizedBox(height: 8),
                  UiProgressBar(
                    value: (average / 100).clamp(0.0, 1.0),
                    showValue: false,
                    intent: meetsTarget ? UiIntent.success : UiIntent.danger,
                  ),
                  if (hasTarget) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Target ${_trimNum(course.targetGrade!)}',
                      style: context.uiText.caption.copyWith(color: meetsTarget ? c.foregroundMuted : c.destructive),
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
        if (coursesWithData.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: UiCallout(
              title: 'No grades logged yet',
              message: 'Add assessments to your courses to see your academic standing here.',
              intent: UiIntent.info,
              icon: Icons.school_outlined,
            ),
          ),
      ],
    );
  }

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({required this.tasks});
  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final completed = tasks.where((t) => t.isCompleted).length;
    final pending = tasks.where((t) => !t.isCompleted).toList();
    final overdue = pending.where((t) => t.dueDate != null && dateOnly(t.dueDate!).isBefore(today)).length;
    final dueSoon = pending
        .where((t) => t.dueDate != null && !dateOnly(t.dueDate!).isBefore(today) && dateOnly(t.dueDate!).difference(today).inDays <= 3)
        .length;
    final rate = tasks.isEmpty ? 0.0 : completed / tasks.length;

    final byPriority = <int, int>{};
    for (final t in pending) {
      byPriority[t.priority] = (byPriority[t.priority] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Tasks',
          subtitle: '${(rate * 100).round()}% complete overall',
          action: UiButton(label: 'View all', variant: UiVariant.link, size: UiSize.sm, onPressed: () => context.push('/todos')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatChip(label: 'Completed', value: '$completed')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Pending', value: '${pending.length}')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Overdue',
                value: '$overdue',
                valueColor: overdue > 0 ? context.uiColors.destructive : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Due soon', value: '$dueSoon')),
          ],
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 12),
          UiCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Pending by priority', style: context.uiText.bodyStrong),
                const SizedBox(height: 12),
                UiCategoryBar(
                  segments: [
                    for (final p in [3, 2, 1, 0])
                      if (byPriority[p] != null)
                        UiCategorySegment(value: byPriority[p]!.toDouble(), label: _taskPriorityLabel(p), color: _taskPriorityColor(context, p)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _JournalNotesSection extends StatelessWidget {
  const _JournalNotesSection({required this.journal, required this.notes});
  final List<JournalData> journal;
  final List<Note> notes;

  @override
  Widget build(BuildContext context) {
    final today = dateOnly(DateTime.now());
    final entryDays = journal.map((j) => dateOnly(j.createdAt)).toSet();
    var streak = 0;
    var cursor = today;
    while (entryDays.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }

    final moodCounts = <String, int>{};
    for (final j in journal) {
      final mood = j.mood;
      if (mood != null && mood.trim().isNotEmpty) {
        moodCounts[mood] = (moodCounts[mood] ?? 0) + 1;
      }
    }
    final totalMoods = moodCounts.values.fold<int>(0, (a, b) => a + b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(title: 'Journal & Notes'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatChip(label: 'Journal entries', value: '${journal.length}')),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Notes', value: '${notes.length}')),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatChip(
                label: 'Writing streak',
                value: streak == 0 ? '0 days' : '$streak day${streak == 1 ? '' : 's'}',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _StatChip(label: 'Moods logged', value: '$totalMoods')),
          ],
        ),
        if (moodCounts.isNotEmpty) ...[
          const SizedBox(height: 12),
          UiCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Mood distribution', style: context.uiText.bodyStrong),
                ),
                const SizedBox(height: 12),
                UiDonutChart(
                  size: 150,
                  slices: [
                    for (final entry in moodCounts.entries) UiDonutSlice(label: entry.key, value: entry.value.toDouble()),
                  ],
                ),
              ],
            ),
          ),
        ] else if (journal.isNotEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: UiCallout(
              title: 'Track your mood',
              message: 'Add a mood when journaling to see your emotional trends here.',
              intent: UiIntent.info,
              icon: Icons.mood_outlined,
            ),
          ),
      ],
    );
  }
}

class _RoutinesSection extends StatelessWidget {
  const _RoutinesSection({required this.routines});
  final List<Routine> routines;

  @override
  Widget build(BuildContext context) {
    final active = routines.where((r) => r.isActive).toList();
    final byTime = <String, int>{};
    for (final r in active) {
      byTime[r.timeOfDay] = (byTime[r.timeOfDay] ?? 0) + 1;
    }
    final withSteps = routines.map((r) => RoutineContent.parse(r.description)).where((c) => c.steps.isNotEmpty).toList();
    final avgCompletion = withSteps.isEmpty ? 0.0 : withSteps.map((c) => c.progress).reduce((a, b) => a + b) / withSteps.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          title: 'Routines',
          subtitle: '${active.length} active',
          action: UiButton(label: 'View all', variant: UiVariant.link, size: UiSize.sm, onPressed: () => context.push('/routines')),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatChip(label: 'Active routines', value: '${active.length}')),
            const SizedBox(width: 12),
            Expanded(
              child: _StatChip(
                label: 'Avg checklist done',
                value: withSteps.isEmpty ? '\u2014' : '${(avgCompletion * 100).round()}%',
              ),
            ),
          ],
        ),
        if (byTime.isNotEmpty) ...[
          const SizedBox(height: 12),
          UiCard(
            padding: const EdgeInsets.all(16),
            child: UiCategoryBar(
              segments: [for (final entry in byTime.entries) UiCategorySegment(value: entry.value.toDouble(), label: entry.key)],
            ),
          ),
        ],
      ],
    );
  }
}
