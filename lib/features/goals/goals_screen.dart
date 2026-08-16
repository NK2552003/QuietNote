import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/goals/goal_editor_screen.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

enum _GoalFilter { all, active, completed, overdue }

final _goalQueryProvider = StateProvider<String>((ref) => '');
final _goalFilterProvider = StateProvider<_GoalFilter>((ref) => _GoalFilter.all);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

List<Map<String, dynamic>> _parseMilestones(String? raw) {
  if (raw == null) return const [];
  try {
    final decoded = jsonDecode(raw) as List;
    return decoded
        .map((e) => {'title': (e as Map)['title'], 'isCompleted': e['isCompleted'] == true})
        .toList();
  } catch (_) {
    return const [];
  }
}

class GoalsScreen extends ConsumerWidget {
  const GoalsScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Goal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal?'),
        content: Text('This removes "${goal.title}" and its milestones. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Delete', style: TextStyle(color: context.uiColors.destructive))),
        ],
      ),
    );
    if (confirmed == true) await ref.read(goalRepositoryProvider).deleteGoal(goal.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goalsAsync = ref.watch(goalsStreamProvider);

    return UiPage(
      header: const UiHeader(
        title: 'Goals',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Turn ambitious vision into clear, achievable milestones.',
      ),
      child: goalsAsync.when(
        loading: () => const _GoalsSkeleton(),
        error: (err, stack) => UiCard(accentColor: context.uiColors.destructive, child: Text('Could not load goals: $err', style: context.uiText.caption.copyWith(color: context.uiColors.destructive))),
        data: (goals) {
          if (goals.isEmpty) return const UiEmptyState(title: 'No active goals', message: 'Set a vision to track your long-term progress.', icon: Icons.flag_outlined);

          final query = ref.watch(_goalQueryProvider);
          final filter = ref.watch(_goalFilterProvider);

          final today = _dateOnly(DateTime.now());
          final activeCount = goals.where((g) => g.progressPercent < 100).length;
          final completedCount = goals.where((g) => g.progressPercent >= 100).length;
          final overdueCount = goals.where((g) => g.progressPercent < 100 && g.deadline != null && _dateOnly(g.deadline!).isBefore(today)).length;

          final q = query.trim().toLowerCase();
          final filtered = goals.where((g) {
            if (q.isNotEmpty) {
              final matches = g.title.toLowerCase().contains(q) || (g.category ?? '').toLowerCase().contains(q);
              if (!matches) return false;
            }
            final isOverdue = g.progressPercent < 100 && g.deadline != null && _dateOnly(g.deadline!).isBefore(today);
            switch (filter) {
              case _GoalFilter.all:
                return true;
              case _GoalFilter.active:
                return g.progressPercent < 100;
              case _GoalFilter.completed:
                return g.progressPercent >= 100;
              case _GoalFilter.overdue:
                return isOverdue;
            }
          }).toList();

          filtered.sort((a, b) {
            final aDone = a.progressPercent >= 100;
            final bDone = b.progressPercent >= 100;
            if (aDone != bDone) return aDone ? 1 : -1;
            if (a.priority != b.priority) return b.priority.compareTo(a.priority);
            if (a.deadline == null && b.deadline == null) return 0;
            if (a.deadline == null) return 1;
            if (b.deadline == null) return -1;
            return a.deadline!.compareTo(b.deadline!);
          });

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _StatCard(label: 'Active', value: '$activeCount')),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Completed', value: '$completedCount')),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Overdue', value: '$overdueCount', valueColor: overdueCount > 0 ? context.uiColors.destructive : null)),
                ],
              ),
              const SizedBox(height: 16),
              UiSearchField(hintText: 'Search goals...', value: query, onChanged: (v) => ref.read(_goalQueryProvider.notifier).state = v),
              const SizedBox(height: 12),
              UiToggleGroup<_GoalFilter>(
                variant: UiToggleGroupVariant.segmented,
                size: UiSize.sm,
                expand: true,
                value: filter,
                onChanged: (v) => ref.read(_goalFilterProvider.notifier).state = v,
                options: const [
                  UiToggleOption(value: _GoalFilter.all, label: 'All'),
                  UiToggleOption(value: _GoalFilter.active, label: 'Active'),
                  UiToggleOption(value: _GoalFilter.completed, label: 'Completed'),
                  UiToggleOption(value: _GoalFilter.overdue, label: 'Overdue', intent: UiIntent.danger),
                ],
              ),
              const SizedBox(height: 16),
              if (filtered.isEmpty)
                UiEmptyState(title: 'Nothing here', message: q.isNotEmpty ? 'Nothing found for "$query".' : 'No goals match this filter.', icon: Icons.search_off_rounded)
              else
                ...filtered.map((goal) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _GoalCard(goal: goal, onTap: () => context.push('/goals/edit/${goal.id}'), onDelete: () => _confirmDelete(context, ref, goal)))),
            ],
          );
        },
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.valueColor});
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return UiCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.uiText.caption),
          const SizedBox(height: 4),
          Text(value, style: context.uiText.heading.copyWith(color: valueColor)),
        ],
      ),
    );
  }
}

class _GoalCard extends ConsumerWidget {
  const _GoalCard({required this.goal, required this.onTap, required this.onDelete});

  final Goal goal;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final milestones = _parseMilestones(goal.milestones);
    final tint = goalCategoryColor(context, goal.category);
    final progress = goal.target == 0 ? 0.0 : (goal.current / goal.target).clamp(0.0, 1.0);
    final isCompleted = goal.progressPercent >= 100;
    final today = _dateOnly(DateTime.now());
    final isOverdue = !isCompleted && goal.deadline != null && _dateOnly(goal.deadline!).isBefore(today);

    return UiCard(
      onTap: onTap,
      accentColor: tint,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(goalCategoryIcon(goal.category), size: 18, color: tint),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      goal.title,
                      style: context.uiText.bodyStrong.copyWith(
                        decoration: isCompleted ? TextDecoration.lineThrough : null,
                        color: isCompleted ? c.foregroundMuted : null,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (goal.category != null)
                          UiBadge(label: goal.category!, intent: UiIntent.neutral, size: UiSize.sm),
                        if (goal.priority > 0)
                          UiBadge(
                            label: const ['', 'Low', 'Medium', 'High'][goal.priority],
                            intent: goal.priority == 3
                                ? UiIntent.danger
                                : goal.priority == 2
                                    ? UiIntent.warning
                                    : UiIntent.info,
                            size: UiSize.sm,
                          ),
                        if (isCompleted)
                          const UiBadge(label: 'Completed', icon: Icons.check_circle_outline, intent: UiIntent.success, size: UiSize.sm)
                        else if (goal.deadline != null)
                          _DeadlineTile(date: goal.deadline!, isOverdue: isOverdue),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              UiProgressCircle(
                value: progress,
                size: 48,
                thickness: 5,
                intent: isCompleted ? UiIntent.success : UiIntent.primary,
                center: Text('${goal.progressPercent}%', style: context.uiText.caption.copyWith(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          UiProgressBar(
            value: progress,
            showValue: false,
            intent: isCompleted ? UiIntent.success : UiIntent.primary,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${_trimNum(goal.current)} / ${_trimNum(goal.target)}',
                style: context.uiText.caption,
              ),
              const Spacer(),
              if (!isCompleted)
                UiButton(
                  label: 'Add +1',
                  variant: UiVariant.ghost,
                  size: UiSize.sm,
                  onPressed: () {
                    final newCurrent = (goal.current + 1).clamp(0.0, goal.target == 0 ? 1.0 : goal.target);
                    final newPercent = goal.target == 0 ? 100 : ((newCurrent / goal.target) * 100).clamp(0, 100).toInt();
                    ref.read(goalRepositoryProvider).updateGoalProgress(goal.id, newCurrent, newPercent, goal.milestones);
                  },
                ),
              UiIconButton(
                icon: Icons.delete_outline,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: 'Delete goal',
                onPressed: onDelete,
              ),
            ],
          ),
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Divider(height: 20),
            Text('Milestones', style: context.uiText.caption),
            const SizedBox(height: 6),
            ...milestones.asMap().entries.map((entry) {
              final index = entry.key;
              final m = entry.value;
              final done = m['isCompleted'] == true;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: UiCheckbox(
                  value: done,
                  size: UiSize.sm,
                  label: m['title'] as String,
                  onChanged: (_) {
                    final updated = List<Map<String, dynamic>>.from(milestones);
                    updated[index]['isCompleted'] = !done;
                    final completedCount = updated.where((e) => e['isCompleted'] == true).length;
                    final newCurrent = (completedCount / updated.length) * goal.target;
                    final newPercent = ((completedCount / updated.length) * 100).toInt();
                    ref.read(goalRepositoryProvider).updateGoalProgress(
                          goal.id,
                          newCurrent,
                          newPercent,
                          jsonEncode(updated),
                        );
                  },
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _DeadlineTile extends StatelessWidget {
  const _DeadlineTile({required this.date, this.isOverdue = false});
  final DateTime date;
  final bool isOverdue;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final day = date.day.toString();
    final month = DateFormat.MMM().format(date); // e.g. "Aug"
    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isOverdue ? c.destructive.withValues(alpha: 0.12) : c.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isOverdue ? c.destructive : c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      child: Text(
        '$day $month',
        style: context.uiText.caption.copyWith(fontWeight: FontWeight.w700, color: isOverdue ? c.destructive : c.foreground),
      ),
    );
  }
}

class _GoalsSkeleton extends StatelessWidget {
  const _GoalsSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: UiCard(loading: true, loadingHeight: 140, child: SizedBox.shrink()),
        ),
      ),
    );
  }
}
