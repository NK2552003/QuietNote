import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/notifications/notification_service.dart';

const int _reminderNone = -1;
const String _recurNone = 'none';
const String _goalNone = '';

const List<UiOption<int>> _reminderOptions = [
  UiOption(value: _reminderNone, label: 'No reminder'),
  UiOption(value: 0, label: 'At due time'),
  UiOption(value: 10, label: '10 minutes before'),
  UiOption(value: 30, label: '30 minutes before'),
  UiOption(value: 60, label: '1 hour before'),
  UiOption(value: 1440, label: '1 day before'),
];

const List<UiOption<String>> _recurrenceOptions = [
  UiOption(value: _recurNone, label: 'Does not repeat'),
  UiOption(value: 'daily', label: 'Daily'),
  UiOption(value: 'weekly', label: 'Weekly'),
  UiOption(value: 'monthly', label: 'Monthly'),
];

const List<UiToggleOption<int>> _priorityOptions = [
  UiToggleOption(value: 0, label: 'None'),
  UiToggleOption(value: 1, label: 'Low', intent: UiIntent.info),
  UiToggleOption(value: 2, label: 'Medium', intent: UiIntent.warning),
  UiToggleOption(value: 3, label: 'High', intent: UiIntent.danger),
];

class TodoEditorScreen extends ConsumerStatefulWidget {
  final String? taskId;
  const TodoEditorScreen({super.key, this.taskId});

  @override
  ConsumerState<TodoEditorScreen> createState() => _TodoEditorScreenState();
}

class _TodoEditorScreenState extends ConsumerState<TodoEditorScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _subtaskController = TextEditingController();

  bool get _isEditing => widget.taskId != null;

  bool _isLoading = false;
  bool _isSaving = false;

  int _priority = 0;
  DateTime? _dueDate;
  int _reminderSel = _reminderNone;
  String _recurrenceSel = _recurNone;
  String _linkedGoalSel = _goalNone;
  String _linkedCourseSel = '';
  List<Map<String, dynamic>> _subtasks = [];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _loadTask();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _detailsController.dispose();
    _subtaskController.dispose();
    super.dispose();
  }

  Future<void> _loadTask() async {
    setState(() => _isLoading = true);
    final task = await ref
        .read(taskRepositoryProvider)
        .getTaskById(widget.taskId!);
    if (task != null && mounted) {
      _titleController.text = task.title;
      _subtitleController.text = task.subtitle;
      _detailsController.text = task.details ?? '';
      _priority = task.priority;
      _dueDate = task.dueDate;
      _recurrenceSel = task.recurrenceRule ?? _recurNone;
      _linkedGoalSel = task.linkedGoalId ?? _goalNone;
      _linkedCourseSel = task.courseId ?? '';
      _reminderSel = task.reminderOffset ?? _reminderNone;
      if (task.subtasks != null) {
        try {
          final decoded = jsonDecode(task.subtasks!) as List;
          _subtasks = decoded
              .map(
                (e) => {
                  'title': (e as Map)['title'],
                  'isCompleted': e['isCompleted'] == true,
                },
              )
              .toList();
        } catch (_) {}
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String? get _headerSubtitle {
    if (!_isEditing) return null;
    final parts = <String>[];
    if (_dueDate != null) {
      parts.add('Due ${DateFormat.yMMMd().format(_dueDate!)}');
    }
    if (_subtasks.isNotEmpty) {
      final done = _subtasks.where((s) => s['isCompleted'] == true).length;
      parts.add('$done/${_subtasks.length} subtasks');
    }
    return parts.isEmpty ? null : parts.join(' \u00b7 ');
  }

  void _addSubtask() {
    final text = _subtaskController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _subtasks.add({'title': text, 'isCompleted': false});
      _subtaskController.clear();
    });
  }

  void _toggleSubtask(int index) {
    setState(
      () => _subtasks[index]['isCompleted'] =
          !(_subtasks[index]['isCompleted'] == true),
    );
  }

  void _removeSubtask(int index) {
    setState(() => _subtasks.removeAt(index));
  }

  Future<void> _pickDueDate() async {
    final base = _dueDate ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(
      () => _dueDate = DateTime(
        date.year,
        date.month,
        date.day,
        base.hour,
        base.minute,
      ),
    );
  }

  Future<void> _pickDueTime() async {
    final base = _dueDate ?? DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    setState(
      () => _dueDate = DateTime(
        base.year,
        base.month,
        base.day,
        time.hour,
        time.minute,
      ),
    );
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the list, even when the form is empty/invalid.
  void _goBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/todos');
    }
  }

  Future<void> _saveTask() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add a task name',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    final subtitle = _subtitleController.text.trim();
    final details = _detailsController.text.trim();
    final subtasksJson = _subtasks.isEmpty ? null : jsonEncode(_subtasks);
    final recurrenceRule = _recurrenceSel == _recurNone ? null : _recurrenceSel;
    final linkedGoalId = _linkedGoalSel.isEmpty ? null : _linkedGoalSel;
    final linkedCourseId = _linkedCourseSel.isEmpty ? null : _linkedCourseSel;
    final reminderOffset = _reminderSel == _reminderNone ? null : _reminderSel;

    late final String taskId;
    if (_isEditing) {
      taskId = widget.taskId!;
      await ref
          .read(taskRepositoryProvider)
          .updateTask(
            taskId,
            title: title,
            subtitle: subtitle,
            details: details.isEmpty ? null : details,
            priority: _priority,
            subtasks: subtasksJson,
            dueDate: _dueDate,
            recurrenceRule: recurrenceRule,
            linkedGoalId: linkedGoalId,
            reminderOffset: reminderOffset,
            courseId: linkedCourseId,
          );
    } else {
      taskId = await ref
          .read(taskRepositoryProvider)
          .addTask(
            title,
            subtitle: subtitle,
            details: details.isEmpty ? null : details,
            priority: _priority,
            subtasks: subtasksJson,
            dueDate: _dueDate,
            recurrenceRule: recurrenceRule,
            linkedGoalId: linkedGoalId,
            reminderOffset: reminderOffset,
            courseId: linkedCourseId,
          );
    }

    if (_dueDate != null && reminderOffset != null) {
      final scheduledTime = _dueDate!.subtract(
        Duration(minutes: reminderOffset),
      );
      if (scheduledTime.isAfter(DateTime.now())) {
        final scheduled = await NotificationService().scheduleReminder(
          taskId.hashCode,
          title,
          subtitle.isEmpty ? 'Task reminder' : subtitle,
          scheduledTime,
          repeatComponents: switch (recurrenceRule) {
            'daily' => DateTimeComponents.time,
            'weekly' => DateTimeComponents.dayOfWeekAndTime,
            'monthly' => DateTimeComponents.dayOfMonthAndTime,
            _ => null,
          },
        );
        if (!scheduled && mounted) {
          UiToast.show(
            context,
            title: 'Task saved without a reminder',
            message:
                'Enable notification permission in Settings to receive it.',
            intent: UiIntent.warning,
          );
        }
      }
    }

    if (!mounted) return;
    // Ensure task stream updates immediately after save.
    ref.invalidate(tasksStreamProvider);
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/todos');
    }
  }

  Future<void> _deleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text(
          'This removes the task and its subtasks. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: context.uiColors.destructive),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await NotificationService().cancelReminder(widget.taskId!.hashCode);
      await ref.read(taskRepositoryProvider).deleteTask(widget.taskId!);
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/todos');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final goalsAsync = ref.watch(goalsStreamProvider);
    final goals = goalsAsync.maybeWhen(
      data: (g) => g,
      orElse: () => const <Goal>[],
    );

    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          onPressed: _goBack,
          tooltip: 'Back',
        ),
        title: _isEditing ? 'Edit Task' : 'New Task',
        subtitle: _headerSubtitle,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteTask,
              tooltip: 'Delete task',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveTask,
          ),
        ],
      ),
      child: _isLoading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.only(top: 48),
                child: CircularProgressIndicator(),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  style: context.uiText.heading,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Task title',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                UiInput(
                  controller: _subtitleController,
                  hintText: 'Add a short description...',
                ),
                const SizedBox(height: 16),
                UiTextarea(
                  controller: _detailsController,
                  label: 'Notes',
                  hintText: 'Add extra details, links, or context...',
                  rows: 3,
                  maxRows: 6,
                  showCounter: false,
                ),
                const SizedBox(height: 20),
                Text('Priority', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                UiToggleGroup<int>(
                  variant: UiToggleGroupVariant.segmented,
                  expand: true,
                  value: _priority,
                  onChanged: (v) => setState(() => _priority = v),
                  options: _priorityOptions,
                ),
                const SizedBox(height: 20),
                Text('Due date', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                if (_dueDate == null)
                  UiButton(
                    label: 'Add due date',
                    variant: UiVariant.outline,
                    leadingIcon: Icons.event_outlined,
                    onPressed: _pickDueDate,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: UiButton(
                          label: DateFormat.yMMMd().format(_dueDate!),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.event_outlined,
                          onPressed: _pickDueDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: UiButton(
                          label: DateFormat.jm().format(_dueDate!),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.schedule_outlined,
                          onPressed: _pickDueTime,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: c.foregroundMuted,
                        tooltip: 'Remove due date',
                        onPressed: () => setState(() {
                          _dueDate = null;
                          _reminderSel = _reminderNone;
                        }),
                      ),
                    ],
                  ),
                if (_dueDate != null) ...[
                  const SizedBox(height: 16),
                  UiSelect<int>(
                    label: 'Reminder',
                    hintText: 'No reminder',
                    value: _reminderSel,
                    options: _reminderOptions,
                    leadingIcon: Icons.notifications_outlined,
                    onChanged: (v) => setState(() => _reminderSel = v),
                  ),
                ],
                const SizedBox(height: 16),
                UiSelect<String>(
                  label: 'Repeat',
                  hintText: 'Does not repeat',
                  value: _recurrenceSel,
                  options: _recurrenceOptions,
                  leadingIcon: Icons.repeat_rounded,
                  onChanged: (v) => setState(() => _recurrenceSel = v),
                ),
                const SizedBox(height: 16),
                UiSelect<String>(
                  label: 'Linked goal',
                  hintText: 'No goal',
                  value: _linkedGoalSel,
                  leadingIcon: Icons.flag_outlined,
                  options: [
                    const UiOption(value: _goalNone, label: 'No goal'),
                    ...goals.map((g) => UiOption(value: g.id, label: g.title)),
                  ],
                  onChanged: (v) => setState(() => _linkedGoalSel = v),
                ),
                const SizedBox(height: 16),
                Builder(
                  builder: (context) {
                    final coursesAsync = ref.watch(coursesStreamProvider);
                    final courses = coursesAsync.value ?? const <Course>[];
                    return UiSelect<String>(
                      label: 'Linked course',
                      hintText: 'No course',
                      value: _linkedCourseSel,
                      leadingIcon: Icons.school_outlined,
                      options: [
                        const UiOption(value: '', label: 'No course'),
                        ...courses.map((c) => UiOption(
                              value: c.id,
                              label: c.code != null ? '${c.code} - ${c.name}' : c.name,
                            )),
                      ],
                      onChanged: (v) => setState(() => _linkedCourseSel = v),
                    );
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Subtasks', style: context.uiText.bodyStrong),
                    if (_subtasks.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_subtasks.where((s) => s['isCompleted'] == true).length}/${_subtasks.length}',
                        style: context.uiText.caption,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (_subtasks.isNotEmpty)
                  ..._subtasks.asMap().entries.map((entry) {
                    final index = entry.key;
                    final st = entry.value;
                    final done = st['isCompleted'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => _toggleSubtask(index),
                            child: Icon(
                              done
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: done ? c.primary : c.foregroundMuted,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              st['title'] as String,
                              style: context.uiText.body.copyWith(
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: done ? c.foregroundMuted : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            color: c.foregroundMuted,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                            onPressed: () => _removeSubtask(index),
                          ),
                        ],
                      ),
                    );
                  }),
                Row(
                  children: [
                    Expanded(
                      child: UiInput(
                        controller: _subtaskController,
                        hintText: 'Add a subtask...',
                        onSubmitted: (_) => _addSubtask(),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      color: c.primary,
                      onPressed: _addSubtask,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
