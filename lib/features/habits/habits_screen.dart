import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/habits/habit_editor_screen.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

enum _HabitFilter { active, archived }

final _habitQueryProvider = StateProvider<String>((ref) => '');
final _habitFilterProvider = StateProvider<_HabitFilter>((ref) => _HabitFilter.active);

class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final habitsAsync = ref.watch(habitsStreamProvider);
    final query = ref.watch(_habitQueryProvider);
    final filter = ref.watch(_habitFilterProvider);
    final c = context.uiColors;

    return UiPage(
      header: const UiHeader(
        title: 'Habits',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Small daily steps lead to remarkable long-term growth.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          habitsAsync.when(
            data: (allHabits) {
              if (allHabits.isEmpty) {
                return const UiEmptyState(
                  title: 'No habits tracked',
                  message: 'Build a small discipline today.',
                  icon: Icons.loop,
                );
              }

              final today = dateOnly(DateTime.now());
              final active = allHabits.where((h) => !h.archived).toList();
              final scheduledToday = active.where((h) => isHabitScheduled(h, today)).toList();

              final q = query.trim().toLowerCase();
              final filtered = allHabits.where((h) {
                if (filter == _HabitFilter.active && h.archived) return false;
                if (filter == _HabitFilter.archived && !h.archived) return false;
                if (q.isEmpty) return true;
                return h.title.toLowerCase().contains(q) || h.subtitle.toLowerCase().contains(q);
              }).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(label: 'Active habits', value: '${active.length}'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          label: 'Best streak',
                          value: active.isEmpty ? '0' : '${active.map((h) => h.streak).reduce((a, b) => a > b ? a : b)}',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(label: 'Due today', value: '${scheduledToday.length}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  UiSearchField(
                    hintText: 'Search habits...',
                    value: query,
                    onChanged: (v) => ref.read(_habitQueryProvider.notifier).state = v,
                  ),
                  const SizedBox(height: 12),
                  UiToggleGroup<_HabitFilter>(
                    variant: UiToggleGroupVariant.segmented,
                    size: UiSize.sm,
                    value: filter,
                    expand: true,
                    onChanged: (v) => ref.read(_habitFilterProvider.notifier).state = v,
                    options: const [
                      UiToggleOption(value: _HabitFilter.active, label: 'Active'),
                      UiToggleOption(value: _HabitFilter.archived, label: 'Archived'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    UiEmptyState(
                      title: 'Nothing here',
                      message: q.isNotEmpty
                          ? 'Nothing found for "$query".'
                          : (filter == _HabitFilter.archived ? 'No archived habits.' : 'No habits match this filter.'),
                      icon: Icons.search_off_rounded,
                    )
                  else
                    ...filtered.map((h) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _HabitCard(habit: h),
                        )),
                ],
              );
            },
            loading: () => const Center(child: Padding(padding: EdgeInsets.only(top: 48), child: CircularProgressIndicator())),
            error: (err, stack) => Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Text('Could not load habits: $err', style: context.uiText.caption.copyWith(color: c.destructive)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.uiText.caption, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value, style: context.uiText.heading),
        ],
      ),
    );
  }
}

class _HabitCard extends ConsumerWidget {
  const _HabitCard({required this.habit});
  final Habit habit;

  static const List<String> _weekdayShort = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final entriesAsync = ref.watch(habitEntriesStreamProvider(habit.id));
    final entries = entriesAsync.value ?? const <HabitEntry>[];
    final doneDays = entries.where((e) => e.isDone).map((e) => dateOnly(e.date)).toSet();
    final color = habitCategoryColor(context, habit.category);
    final today = dateOnly(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));
    final streak = currentStreakFor(habit, doneDays);
    final isDoneToday = doneDays.contains(today);

    return UiCard(
      onTap: () => context.push('/habits/${habit.id}'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                alignment: Alignment.center,
                child: Icon(habitCategoryIcon(habit.category), size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(habit.title, style: context.uiText.bodyStrong),
                    const SizedBox(height: 2),
                    Text(
                      habitFrequencyLabel(habit.frequencyType, habit.daysOfWeek, habit.intervalDays),
                      style: context.uiText.caption,
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(habitRepositoryProvider).toggleEntry(habit.id, today),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDoneToday ? color : Colors.transparent,
                    border: Border.all(color: isDoneToday ? color : c.border, width: 2),
                  ),
                  child: isDoneToday ? Icon(Icons.check, size: 18, color: c.surface) : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(7, (i) {
              final day = weekDays[i];
              final isDone = doneDays.contains(day);
              final isToday = day == today;
              final scheduled = isHabitScheduled(habit, day);
              final isMissed = !isDone && scheduled && day.isBefore(today);

              Color bg = Colors.transparent;
              Color fg = c.foregroundMuted;
              Border? border = Border.all(color: c.border, width: 1);
              if (isDone) {
                bg = color;
                fg = c.surface;
                border = null;
              } else if (isMissed) {
                border = Border.all(color: c.destructive.withValues(alpha: 0.5), width: 1.2);
                fg = c.destructive;
              } else if (!scheduled) {
                border = null;
                fg = c.foregroundSubtle;
              } else if (isToday) {
                border = Border.all(color: color, width: 1.5);
              }

              return Expanded(
                child: GestureDetector(
                  onTap: !scheduled ? null : () => ref.read(habitRepositoryProvider).toggleEntry(habit.id, day),
                  child: Column(
                    children: [
                      Text(_weekdayShort[i], style: context.uiText.caption.copyWith(color: c.foregroundMuted)),
                      const SizedBox(height: 4),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: border),
                        alignment: Alignment.center,
                        child: isDone
                            ? Icon(Icons.check, size: 14, color: fg)
                            : Text('${day.day}', style: context.uiText.bodyStrong.copyWith(color: fg, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.local_fire_department_rounded, size: 15, color: streak > 0 ? color : c.foregroundMuted),
              const SizedBox(width: 4),
              Text(
                streak > 0 ? '$streak day streak' : 'No streak yet',
                style: context.uiText.caption.copyWith(color: streak > 0 ? color : c.foregroundMuted),
              ),
              if (habit.goalTarget != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.track_changes_outlined, size: 13, color: c.foregroundMuted),
                const SizedBox(width: 4),
                Text(
                  'Goal: ${habit.goalTarget!.toStringAsFixed(habit.goalTarget! == habit.goalTarget!.roundToDouble() ? 0 : 1)}${habit.goalUnit != null ? ' ${habit.goalUnit}' : ''}',
                  style: context.uiText.caption,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
