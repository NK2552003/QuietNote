import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/habits/habit_editor_screen.dart';

class HabitDetailScreen extends ConsumerWidget {
  final String habitId;
  const HabitDetailScreen({super.key, required this.habitId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsStreamProvider);
    final entriesAsync = ref.watch(habitEntriesStreamProvider(habitId));
    final c = context.uiColors;

    return habitsAsync.when(
      data: (habits) {
        final habit = habits.where((h) => h.id == habitId).firstOrNull;
        if (habit == null) {
          return UiPage(
            header: UiHeader(
              leading: UiIconButton(
                icon: Icons.arrow_back,
                variant: UiVariant.ghost,
                onPressed: () => context.canPop() ? context.pop() : context.go('/habits'),
              ),
              title: 'Habit',
            ),
            child: const UiEmptyState(
              title: 'Habit not found',
              message: 'It may have been deleted.',
              icon: Icons.search_off_rounded,
            ),
          );
        }

        final entries = entriesAsync.value ?? const <HabitEntry>[];
        final doneDays = entries.where((e) => e.isDone).map((e) => dateOnly(e.date)).toSet();
        final currentStreak = currentStreakFor(habit, doneDays);
        final bestStreak = bestStreakFor(habit, doneDays);
        final completionRate = completionRateFor(habit, doneDays, days: 30);
        final color = habitCategoryColor(context, habit.category);
        final today = dateOnly(DateTime.now());
        final isDoneToday = doneDays.contains(today);

        return UiPage(
          header: UiHeader(
            leading: UiIconButton(
              icon: Icons.arrow_back,
              variant: UiVariant.ghost,
              onPressed: () => context.canPop() ? context.pop() : context.go('/habits'),
            ),
            title: habit.title,
            subtitle: habitFrequencyLabel(habit.frequencyType, habit.daysOfWeek, habit.intervalDays),
            actions: [
              UiIconButton(
                icon: habit.archived ? Icons.unarchive_outlined : Icons.archive_outlined,
                variant: UiVariant.ghost,
                tooltip: habit.archived ? 'Unarchive' : 'Archive',
                onPressed: () => ref.read(habitRepositoryProvider).setArchived(habit.id, !habit.archived),
              ),
              UiIconButton(
                icon: Icons.edit_outlined,
                variant: UiVariant.ghost,
                tooltip: 'Edit habit',
                onPressed: () => context.push('/habits/edit/${habit.id}'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (habit.subtitle.isNotEmpty) ...[
                Text(habit.subtitle, style: context.uiText.body.copyWith(color: c.foregroundMuted)),
                const SizedBox(height: 16),
              ],
              Row(
                children: [
                  Icon(habitCategoryIcon(habit.category), size: 18, color: color),
                  const SizedBox(width: 6),
                  Text(habit.category ?? 'Other', style: context.uiText.caption.copyWith(color: color)),
                  if (habit.priority > 0) ...[
                    const SizedBox(width: 8),
                    UiBadge(
                      label: habitPriorityOptions[habit.priority].label,
                      intent: habitPriorityOptions[habit.priority].intent ?? UiIntent.neutral,
                    ),
                  ],
                  if (habit.archived) ...[
                    const SizedBox(width: 8),
                    const UiBadge(label: 'Archived', intent: UiIntent.neutral),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _StatCard(label: 'Streak', value: '$currentStreak', icon: Icons.local_fire_department_rounded, color: color)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Best streak', value: '$bestStreak', icon: Icons.emoji_events_outlined, color: color)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: '30-day rate', value: '${(completionRate * 100).round()}%', icon: Icons.insights_rounded, color: color)),
                ],
              ),
              const SizedBox(height: 16),
              UiButton(
                label: isDoneToday ? 'Marked done today' : 'Mark today done',
                leadingIcon: isDoneToday ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                variant: isDoneToday ? UiVariant.primary : UiVariant.outline,
                onPressed: () => ref.read(habitRepositoryProvider).toggleEntry(habit.id, today),
              ),
              const SizedBox(height: 20),
              UiTabs(
                variant: UiTabsVariant.segmented,
                items: [
                  UiTabItem(
                    label: 'Calendar',
                    icon: Icons.calendar_month_outlined,
                    content: _CalendarTab(habit: habit, doneDays: doneDays, color: color),
                  ),
                  UiTabItem(
                    label: 'Statistics',
                    icon: Icons.bar_chart_rounded,
                    content: _StatisticsTab(habit: habit, entries: entries, doneDays: doneDays, color: color),
                  ),
                ],
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.only(top: 48), child: CircularProgressIndicator())),
      error: (err, stack) => UiPage(
        child: Text('Could not load habit: $err', style: context.uiText.caption.copyWith(color: c.destructive)),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: context.uiText.caption, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: context.uiText.title),
        ],
      ),
    );
  }
}

class _CalendarTab extends ConsumerStatefulWidget {
  const _CalendarTab({required this.habit, required this.doneDays, required this.color});
  final Habit habit;
  final Set<DateTime> doneDays;
  final Color color;

  @override
  ConsumerState<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<_CalendarTab> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  static const List<String> _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final today = dateOnly(DateTime.now());
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1; // Mon=1..Sun=7 -> 0..6

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  UiIconButton(
                    icon: Icons.chevron_left,
                    variant: UiVariant.ghost,
                    tooltip: 'Previous month',
                    onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                  ),
                  Text(DateFormat.yMMMM().format(_month), style: context.uiText.bodyStrong),
                  UiIconButton(
                    icon: Icons.chevron_right,
                    variant: UiVariant.ghost,
                    tooltip: 'Next month',
                    onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: _weekdays
                    .map((d) => Expanded(
                          child: Center(
                            child: Text(d, style: context.uiText.caption.copyWith(color: c.foregroundMuted)),
                          ),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: leadingBlanks + daysInMonth,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
                itemBuilder: (context, index) {
                  if (index < leadingBlanks) return const SizedBox.shrink();
                  final day = DateTime(_month.year, _month.month, index - leadingBlanks + 1);
                  final isToday = day == today;
                  final isDone = widget.doneDays.contains(day);
                  final scheduled = isHabitScheduled(widget.habit, day);
                  final isMissed = !isDone && scheduled && day.isBefore(today);

                  Color bg = Colors.transparent;
                  Color fg = c.foreground;
                  Border? border;
                  if (isDone) {
                    bg = widget.color.withValues(alpha: 0.18);
                    fg = widget.color;
                    border = Border.all(color: widget.color, width: 1.5);
                  } else if (isMissed) {
                    border = Border.all(color: c.destructive.withValues(alpha: 0.5), width: 1.2);
                    fg = c.destructive;
                  } else if (!scheduled) {
                    fg = c.foregroundSubtle;
                  } else if (isToday) {
                    border = Border.all(color: c.border, width: 1.5);
                  }

                  return GestureDetector(
                    onTap: !scheduled
                        ? null
                        : () => ref.read(habitRepositoryProvider).toggleEntry(widget.habit.id, day),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: border),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: context.uiText.caption.copyWith(
                            color: fg,
                            fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 14,
                children: [
                  _LegendDot(color: widget.color, filled: true, label: 'Done'),
                  _LegendDot(color: c.destructive, filled: false, label: 'Missed'),
                  _LegendDot(color: c.foregroundSubtle, filled: false, label: 'Not scheduled'),
                ],
              ),
            ],
          ),
        ),
        if (widget.habit.notes != null && widget.habit.notes!.isNotEmpty) ...[
          const SizedBox(height: 12),
          UiCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.notes_rounded, size: 16, color: c.foregroundMuted),
                    const SizedBox(width: 6),
                    Text('Notes', style: context.uiText.bodyStrong),
                  ],
                ),
                const SizedBox(height: 8),
                Text(widget.habit.notes!, style: context.uiText.body),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.filled, required this.label});
  final Color color;
  final bool filled;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? color.withValues(alpha: 0.3) : Colors.transparent,
            border: Border.all(color: color, width: 1.2),
          ),
        ),
        const SizedBox(width: 5),
        Text(label, style: context.uiText.caption),
      ],
    );
  }
}

class _StatisticsTab extends StatelessWidget {
  const _StatisticsTab({required this.habit, required this.entries, required this.doneDays, required this.color});
  final Habit habit;
  final List<HabitEntry> entries;
  final Set<DateTime> doneDays;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final scorePercent = completionRateFor(habit, doneDays, days: 30);
    final totalCompletions = doneDays.length;
    final currentStreak = currentStreakFor(habit, doneDays);
    final bestStreak = bestStreakFor(habit, doneDays);

    final now = DateTime.now();
    final months = List.generate(6, (i) => DateTime(now.year, now.month - (5 - i)));
    final chartData = months.map((m) {
      final count = doneDays.where((d) => d.year == m.year && d.month == m.month).length;
      return UiChartPoint(label: DateFormat.MMM().format(m), values: [count.toDouble()]);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        UiCard(
          child: Column(
            children: [
              Text('Habit score', style: context.uiText.caption.copyWith(color: c.foregroundMuted)),
              const SizedBox(height: 12),
              UiProgressCircle(
                value: scorePercent,
                size: 140,
                thickness: 10,
                intent: scorePercent > 0.7 ? UiIntent.success : (scorePercent > 0.4 ? UiIntent.warning : UiIntent.danger),
                center: Text('${(scorePercent * 100).round()}', style: context.uiText.heading),
              ),
              const SizedBox(height: 4),
              Text('Last 30 scheduled days', style: context.uiText.caption.copyWith(color: c.foregroundMuted)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _StatCard(label: 'Total done', value: '$totalCompletions', icon: Icons.check_circle_outline, color: color)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'Streak', value: '$currentStreak', icon: Icons.local_fire_department_rounded, color: color)),
            const SizedBox(width: 12),
            Expanded(child: _StatCard(label: 'Best', value: '$bestStreak', icon: Icons.emoji_events_outlined, color: color)),
          ],
        ),
        const SizedBox(height: 12),
        UiCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Completions by month', style: context.uiText.bodyStrong),
              const SizedBox(height: 12),
              UiChart(
                data: chartData,
                series: [UiChartSeries(name: 'Done', color: color, type: UiChartSeriesType.bar)],
                height: 180,
                showLegend: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
