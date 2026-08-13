import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';

/// Preset goal categories. Shared with the goals list so tags stay visually
/// consistent — each maps to one of the app's chart-series colors.
const List<String> goalCategoryNames = [
  'Career',
  'Health',
  'Finance',
  'Learning',
  'Personal',
  'Relationships',
  'Travel',
  'Other',
];

const List<IconData> _goalCategoryIcons = [
  Icons.work_outline_rounded,
  Icons.favorite_outline_rounded,
  Icons.savings_outlined,
  Icons.school_outlined,
  Icons.self_improvement_rounded,
  Icons.people_outline_rounded,
  Icons.flight_takeoff_rounded,
  Icons.star_outline_rounded,
];

int goalCategoryIndex(String? category) {
  if (category == null) return goalCategoryNames.length - 1;
  final i = goalCategoryNames.indexOf(category);
  return i == -1 ? goalCategoryNames.length - 1 : i;
}

Color goalCategoryColor(BuildContext context, String? category) {
  const series = UiPalette.series;
  return series[goalCategoryIndex(category) % series.length];
}

IconData goalCategoryIcon(String? category) =>
    _goalCategoryIcons[goalCategoryIndex(category)];

const List<UiToggleOption<int>> _priorityOptions = [
  UiToggleOption(value: 0, label: 'None'),
  UiToggleOption(value: 1, label: 'Low', intent: UiIntent.info),
  UiToggleOption(value: 2, label: 'Medium', intent: UiIntent.warning),
  UiToggleOption(value: 3, label: 'High', intent: UiIntent.danger),
];

class GoalEditorScreen extends ConsumerStatefulWidget {
  final String? goalId;
  const GoalEditorScreen({super.key, this.goalId});

  @override
  ConsumerState<GoalEditorScreen> createState() => _GoalEditorScreenState();
}

class _GoalEditorScreenState extends ConsumerState<GoalEditorScreen> {
  final _titleController = TextEditingController();
  final _targetController = TextEditingController();
  final _currentController = TextEditingController();
  final _milestoneController = TextEditingController();

  bool get _isEditing => widget.goalId != null;

  bool _isLoading = false;
  bool _isSaving = false;

  String _category = goalCategoryNames.first;
  int _priority = 0;
  DateTime? _deadline;
  String _linkedCourseSel = '';
  List<Map<String, dynamic>> _milestones = [];

  @override
  void initState() {
    super.initState();
    _targetController.text = '10';
    _currentController.text = '0';
    if (_isEditing) _loadGoal();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _targetController.dispose();
    _currentController.dispose();
    _milestoneController.dispose();
    super.dispose();
  }

  Future<void> _loadGoal() async {
    setState(() => _isLoading = true);
    final goal = await ref
        .read(goalRepositoryProvider)
        .getGoalById(widget.goalId!);
    if (goal != null && mounted) {
      _titleController.text = goal.title;
      _targetController.text = _trimNum(goal.target);
      _currentController.text = _trimNum(goal.current);
      _category = goal.category ?? goalCategoryNames.first;
      _priority = goal.priority;
      _deadline = goal.deadline;
      _linkedCourseSel = goal.courseId ?? '';
      if (goal.milestones != null) {
        try {
          final decoded = jsonDecode(goal.milestones!) as List;
          _milestones = decoded
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

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  void _addMilestone() {
    final text = _milestoneController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _milestones.add({'title': text, 'isCompleted': false});
      _milestoneController.clear();
    });
  }

  void _removeMilestone(int index) {
    setState(() => _milestones.removeAt(index));
  }

  void _reorderMilestone(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _milestones.length) return;
    setState(() {
      final item = _milestones.removeAt(index);
      _milestones.insert(newIndex, item);
    });
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _deadline = date);
  }

  Future<void> _saveGoal() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add a goal name',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final target = double.tryParse(_targetController.text.trim()) ?? 1.0;
    final current = (double.tryParse(_currentController.text.trim()) ?? 0.0)
        .clamp(0.0, target == 0 ? 0.0 : target);
    final milestonesJson = _milestones.isEmpty ? null : jsonEncode(_milestones);
    final linkedCourseId = _linkedCourseSel.isEmpty ? null : _linkedCourseSel;

    late final String goalId;
    if (_isEditing) {
      goalId = widget.goalId!;
      await ref
          .read(goalRepositoryProvider)
          .updateGoal(
            goalId,
            title: title,
            target: target,
            current: current,
            deadline: _deadline,
            category: _category,
            priority: _priority,
            milestones: milestonesJson,
            courseId: linkedCourseId,
          );
    } else {
      goalId = await ref
          .read(goalRepositoryProvider)
          .addGoal(
            title,
            target,
            current: current,
            deadline: _deadline,
            category: _category,
            priority: _priority,
            milestones: milestonesJson,
            courseId: linkedCourseId,
          );
    }

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/goals');
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the list, even when the form is empty/invalid.
  void _goBack() {
    context.canPop() ? context.pop() : context.go('/goals');
  }

  Future<void> _deleteGoal() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete goal?'),
        content: const Text(
          'This removes the goal and its milestones. This can\'t be undone.',
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
      await ref.read(goalRepositoryProvider).deleteGoal(widget.goalId!);
      if (!mounted) return;
      context.canPop() ? context.pop() : context.go('/goals');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;

    return UiPage(
      header: UiHeader(
        leading: UiIconButton(
          icon: Icons.arrow_back,
          variant: UiVariant.ghost,
          onPressed: _goBack,
          tooltip: 'Back',
        ),
        title: _isEditing ? 'Edit Goal' : 'New Goal',
        subtitle: _isEditing && _deadline != null
            ? 'Due ${DateFormat.yMMMd().format(_deadline!)}'
            : null,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteGoal,
              tooltip: 'Delete goal',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveGoal,
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
                    hintText: 'Goal title (e.g. Read 50 books)',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Category', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: goalCategoryNames.map((name) {
                    final selected = name == _category;
                    final color = goalCategoryColor(context, name);
                    return GestureDetector(
                      onTap: () => setState(() => _category = name),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? color.withValues(alpha: 0.15)
                              : c.surfaceMuted,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: selected ? color : c.border,
                            width: selected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              goalCategoryIcon(name),
                              size: 15,
                              color: selected ? color : c.foregroundMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              name,
                              style: context.uiText.caption.copyWith(
                                color: selected ? color : c.foregroundMuted,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: UiField(
                        label: 'Target',
                        child: UiInput(
                          controller: _targetController,
                          hintText: '50',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          leadingIcon: Icons.flag_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: UiField(
                        label: 'Current progress',
                        child: UiInput(
                          controller: _currentController,
                          hintText: '0',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          leadingIcon: Icons.trending_up_rounded,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Deadline', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                if (_deadline == null)
                  UiButton(
                    label: 'Add deadline',
                    variant: UiVariant.outline,
                    leadingIcon: Icons.event_outlined,
                    onPressed: _pickDeadline,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: UiButton(
                          label: DateFormat.yMMMd().format(_deadline!),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.event_outlined,
                          onPressed: _pickDeadline,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: c.foregroundMuted,
                        tooltip: 'Remove deadline',
                        onPressed: () => setState(() => _deadline = null),
                      ),
                    ],
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
                    Text('Milestones', style: context.uiText.bodyStrong),
                    if (_milestones.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_milestones.where((m) => m['isCompleted'] == true).length}/${_milestones.length}',
                        style: context.uiText.caption,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                if (_milestones.isNotEmpty)
                  ..._milestones.asMap().entries.map((entry) {
                    final index = entry.key;
                    final m = entry.value;
                    final done = m['isCompleted'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(
                              () => _milestones[index]['isCompleted'] = !done,
                            ),
                            child: Icon(
                              done
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: done ? c.primary : c.foregroundMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              m['title'],
                              style: context.uiText.body.copyWith(
                                color: done ? c.foregroundMuted : null,
                                decoration: done
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_upward, size: 16),
                            color: c.foregroundMuted,
                            tooltip: 'Move up',
                            onPressed: index == 0
                                ? null
                                : () => _reorderMilestone(index, -1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            color: c.foregroundMuted,
                            tooltip: 'Move down',
                            onPressed: index == _milestones.length - 1
                                ? null
                                : () => _reorderMilestone(index, 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            color: c.foregroundMuted,
                            tooltip: 'Remove milestone',
                            onPressed: () => _removeMilestone(index),
                          ),
                        ],
                      ),
                    );
                  }),
                Row(
                  children: [
                    Expanded(
                      child: UiInput(
                        controller: _milestoneController,
                        hintText: 'Add a milestone...',
                        onSubmitted: (_) => _addMilestone(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UiIconButton(
                      icon: Icons.add,
                      variant: UiVariant.outline,
                      onPressed: _addMilestone,
                      tooltip: 'Add milestone',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
