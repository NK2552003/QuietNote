import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/branding/quietnote_mark.dart';

enum _TodoFilter { all, today, overdue, upcoming, completed }

final _todoQueryProvider = StateProvider<String>((ref) => '');
final _todoFilterProvider = StateProvider<_TodoFilter>((ref) => _TodoFilter.all);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

String _dueLabel(DateTime due) {
  final today = _dateOnly(DateTime.now());
  final day = _dateOnly(due);
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today, ${DateFormat.jm().format(due)}';
  if (diff == 1) return 'Tomorrow, ${DateFormat.jm().format(due)}';
  if (diff == -1) return 'Yesterday, ${DateFormat.jm().format(due)}';
  if (diff > 1 && diff < 7) return '${DateFormat.E().format(due)}, ${DateFormat.jm().format(due)}';
  return DateFormat.yMMMd().format(due);
}

Color _priorityColor(BuildContext context, int priority) {
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

class TodosScreen extends ConsumerWidget {
  const TodosScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Task task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: Text('This removes "${task.title}" and its subtasks. This can\'t be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: context.uiColors.destructive)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(taskRepositoryProvider).deleteTask(task.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(tasksStreamProvider);
    final goalsAsync = ref.watch(goalsStreamProvider);
    final query = ref.watch(_todoQueryProvider);
    final filter = ref.watch(_todoFilterProvider);

    final goalTitles = <String, String>{
      for (final g in goalsAsync.maybeWhen(data: (g) => g, orElse: () => const <Goal>[])) g.id: g.title,
    };

    return UiPage(
      header: const UiHeader(
        title: 'Todos',
        leading: QuietNoteMark(size: 38),
        subtitle: 'Clear your mind, capture your tasks & conquer your day.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          tasksAsync.when(
            data: (tasks) {
              if (tasks.isEmpty) {
                return const UiEmptyState(
                  title: 'No tasks',
                  message: 'You have caught up with everything.',
                  icon: Icons.check_circle_outline,
                );
              }

              final today = _dateOnly(DateTime.now());
              final openCount = tasks.where((t) => !t.isCompleted).length;
              final dueTodayCount = tasks
                  .where((t) => !t.isCompleted && t.dueDate != null && _dateOnly(t.dueDate!) == today)
                  .length;

              final q = query.trim().toLowerCase();
              final filtered = tasks.where((t) {
                if (q.isNotEmpty) {
                  final matches = t.title.toLowerCase().contains(q) ||
                      t.subtitle.toLowerCase().contains(q) ||
                      (t.details ?? '').toLowerCase().contains(q);
                  if (!matches) return false;
                }
                switch (filter) {
                  case _TodoFilter.all:
                    return true;
                  case _TodoFilter.completed:
                    return t.isCompleted;
                  case _TodoFilter.today:
                    return !t.isCompleted && t.dueDate != null && _dateOnly(t.dueDate!) == today;
                  case _TodoFilter.overdue:
                    return !t.isCompleted && t.dueDate != null && _dateOnly(t.dueDate!).isBefore(today);
                  case _TodoFilter.upcoming:
                    return !t.isCompleted && t.dueDate != null && _dateOnly(t.dueDate!).isAfter(today);
                }
              }).toList();

              // Incomplete first, then by priority (desc), then by due date
              // (soonest / most overdue first, undated tasks last).
              filtered.sort((a, b) {
                if (a.isCompleted != b.isCompleted) return a.isCompleted ? 1 : -1;
                if (a.priority != b.priority) return b.priority.compareTo(a.priority);
                if (a.dueDate == null && b.dueDate == null) return 0;
                if (a.dueDate == null) return 1;
                if (b.dueDate == null) return -1;
                return a.dueDate!.compareTo(b.dueDate!);
              });

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: UiCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Open', style: context.uiText.caption),
                              const SizedBox(height: 4),
                              Text('$openCount', style: context.uiText.heading),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: UiCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Due today', style: context.uiText.caption),
                              const SizedBox(height: 4),
                              Text('$dueTodayCount', style: context.uiText.heading),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  UiSearchField(
                    hintText: 'Search tasks...',
                    value: query,
                    onChanged: (v) => ref.read(_todoQueryProvider.notifier).state = v,
                  ),
                  const SizedBox(height: 12),
                  // UiToggleGroup(expand: true) already fits every option
                  // into a single row (each shrinks to share the available
                  // width) instead of wrapping, so no extra scroll wrapper
                  // is needed here. Wrapping it in a horizontally-scrolling
                  // SingleChildScrollView (as this used to) hands the
                  // Expanded() options inside it unbounded width and
                  // crashes the layout — which was blanking this whole
                  // screen.
                  UiToggleGroup<_TodoFilter>(
                    variant: UiToggleGroupVariant.segmented,
                    size: UiSize.sm,
                    expand: true,
                    value: filter,
                    onChanged: (v) => ref.read(_todoFilterProvider.notifier).state = v,
                    options: const <UiToggleOption<_TodoFilter>>[
                      UiToggleOption(value: _TodoFilter.all, label: 'All'),
                      UiToggleOption(value: _TodoFilter.today, label: 'Today'),
                      UiToggleOption(value: _TodoFilter.overdue, label: 'Overdue', intent: UiIntent.danger),
                      UiToggleOption(value: _TodoFilter.upcoming, label: 'Upcoming'),
                      UiToggleOption(value: _TodoFilter.completed, label: 'Done'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (filtered.isEmpty)
                    UiEmptyState(
                      title: 'Nothing here',
                      message: q.isNotEmpty ? 'Nothing found for "$query".' : 'No tasks match this filter.',
                      icon: Icons.search_off_rounded,
                    )
                  else
                    ...filtered.map((task) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TaskCard(
                            task: task,
                            goalTitle: task.linkedGoalId == null ? null : goalTitles[task.linkedGoalId],
                            onToggle: () => ref.read(taskRepositoryProvider).toggleCompletionWithRecurrence(task),
                            onDelete: () => _confirmDelete(context, ref, task),
                            onTap: () => context.push('/todos/edit/${task.id}'),
                          ),
                        )),
                ],
              );
            },
            loading: () => Column(
              children: List.generate(
                4,
                (_) => const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: UiCard(loading: true, loadingHeight: 76, child: SizedBox.shrink()),
                ),
              ),
            ),
            error: (err, stack) => UiCard(
              accentColor: context.uiColors.destructive,
              child: Text(
                'Could not load tasks: $err',
                style: context.uiText.caption.copyWith(color: context.uiColors.destructive),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.goalTitle,
    required this.onToggle,
    required this.onDelete,
    required this.onTap,
  });

  final Task task;
  final String? goalTitle;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;

    List<dynamic> subtasks = [];
    if (task.subtasks != null) {
      try {
        subtasks = jsonDecode(task.subtasks!);
      } catch (_) {}
    }
    final subtasksDone = subtasks.where((s) => s['isCompleted'] == true).length;

    final today = _dateOnly(DateTime.now());
    final isOverdue = task.dueDate != null && !task.isCompleted && _dateOnly(task.dueDate!).isBefore(today);
    final isDueToday = task.dueDate != null && _dateOnly(task.dueDate!) == today;
    final dueColor = task.isCompleted
        ? c.foregroundMuted
        : isOverdue
            ? c.destructive
            : isDueToday
                ? c.warning
                : c.foregroundMuted;

    return UiCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.only(top: 3, right: 12),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: task.isCompleted ? c.primary : c.border, width: 2),
                  color: task.isCompleted ? c.primary : Colors.transparent,
                ),
                child: task.isCompleted ? Icon(Icons.check, size: 16, color: c.surface) : null,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (task.priority > 0)
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: _priorityColor(context, task.priority), shape: BoxShape.circle),
                      ),
                    Expanded(
                      child: Text(
                        task.title,
                        style: context.uiText.bodyStrong.copyWith(
                          decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                          color: task.isCompleted ? c.foregroundMuted : null,
                        ),
                      ),
                    ),
                    if (task.recurrenceRule != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(Icons.repeat_rounded, size: 14, color: c.foregroundMuted),
                      ),
                  ],
                ),
                if (task.subtitle.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(task.subtitle, style: context.uiText.caption),
                  ),
                if (task.details != null && task.details!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      task.details!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.uiText.caption.copyWith(color: c.foregroundSubtle),
                    ),
                  ),
                if (task.dueDate != null || subtasks.isNotEmpty || goalTitle != null) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (task.dueDate != null)
                        _MetaChip(icon: Icons.schedule_rounded, label: _dueLabel(task.dueDate!), color: dueColor),
                      if (subtasks.isNotEmpty)
                        _MetaChip(
                          icon: Icons.checklist_rounded,
                          label: '$subtasksDone/${subtasks.length}',
                          color: c.foregroundMuted,
                        ),
                      if (goalTitle != null)
                        _MetaChip(icon: Icons.flag_rounded, label: goalTitle!, color: c.foregroundMuted),
                    ],
                  ),
                ],
                if (subtasks.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: subtasks.take(4).map((st) {
                        final isStCompleted = st['isCompleted'] == true;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(
                                isStCompleted ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                size: 16,
                                color: isStCompleted ? c.primary : c.border,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  st['title'],
                                  style: context.uiText.caption.copyWith(
                                    decoration: isStCompleted ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: c.foregroundMuted,
            tooltip: 'Delete task',
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(label, style: context.uiText.caption.copyWith(color: color)),
      ],
    );
  }
}
