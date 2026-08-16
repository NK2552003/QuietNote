import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/notifications/notification_service.dart';

/// Preset habit categories, shared with the habit list/detail screens so
/// the little colored icon stays consistent everywhere a habit shows up.
const List<String> habitCategoryNames = [
  'Health',
  'Fitness',
  'Study',
  'Mindfulness',
  'Productivity',
  'Social',
  'Sleep',
  'Other',
];

const List<IconData> _habitCategoryIcons = [
  Icons.favorite_outline_rounded,
  Icons.directions_run_rounded,
  Icons.school_outlined,
  Icons.self_improvement_rounded,
  Icons.bolt_outlined,
  Icons.people_outline_rounded,
  Icons.bedtime_outlined,
  Icons.star_outline_rounded,
];

int habitCategoryIndex(String? category) {
  if (category == null) return habitCategoryNames.length - 1;
  final i = habitCategoryNames.indexOf(category);
  return i == -1 ? habitCategoryNames.length - 1 : i;
}

Color habitCategoryColor(BuildContext context, String? category) {
  const series = UiPalette.series;
  return series[habitCategoryIndex(category) % series.length];
}

IconData habitCategoryIcon(String? category) =>
    _habitCategoryIcons[habitCategoryIndex(category)];

const List<UiToggleOption<int>> habitPriorityOptions = [
  UiToggleOption(value: 0, label: 'None'),
  UiToggleOption(value: 1, label: 'Low', intent: UiIntent.info),
  UiToggleOption(value: 2, label: 'Medium', intent: UiIntent.warning),
  UiToggleOption(value: 3, label: 'High', intent: UiIntent.danger),
];

const List<String> _weekdayShort = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

String habitFrequencyLabel(
  String frequencyType,
  String? daysOfWeek,
  int? intervalDays,
) {
  switch (frequencyType) {
    case 'daily':
      return 'Every day';
    case 'specificDays':
      if (daysOfWeek == null || daysOfWeek.isEmpty) return 'No days selected';
      return daysOfWeek
          .split(',')
          .map((i) => _weekdayShort[int.parse(i)])
          .join(' · ');
    case 'interval':
      return 'Every ${intervalDays ?? 2} days';
    default:
      return '';
  }
}

class HabitEditorScreen extends ConsumerStatefulWidget {
  final String? habitId;
  const HabitEditorScreen({super.key, this.habitId});

  @override
  ConsumerState<HabitEditorScreen> createState() => _HabitEditorScreenState();
}

class _HabitEditorScreenState extends ConsumerState<HabitEditorScreen> {
  final _titleController = TextEditingController();
  final _subtitleController = TextEditingController();
  final _goalTargetController = TextEditingController();
  final _goalUnitController = TextEditingController();
  final _notesController = TextEditingController();

  bool get _isEditing => widget.habitId != null;
  bool _isLoading = false;
  bool _isSaving = false;

  String _category = habitCategoryNames.first;
  int _priority = 0;
  String _frequencyType = 'daily';
  List<int> _selectedDays = [];
  int _intervalDays = 2;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  TimeOfDay? _reminderTime;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadHabit();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _goalTargetController.dispose();
    _goalUnitController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadHabit() async {
    setState(() => _isLoading = true);
    final habit = await ref
        .read(habitRepositoryProvider)
        .getHabitById(widget.habitId!);
    if (habit != null && mounted) {
      _titleController.text = habit.title;
      _subtitleController.text = habit.subtitle;
      _category = habit.category ?? habitCategoryNames.first;
      _priority = habit.priority;
      _frequencyType = habit.frequencyType;
      _selectedDays = habit.daysOfWeek == null || habit.daysOfWeek!.isEmpty
          ? []
          : habit.daysOfWeek!.split(',').map(int.parse).toList();
      _intervalDays = habit.intervalDays ?? 2;
      _startDate = habit.startDate ?? DateTime.now();
      _endDate = habit.endDate;
      _reminderTime = habit.reminderTime == null
          ? null
          : TimeOfDay.fromDateTime(habit.reminderTime!);
      if (habit.goalTarget != null) {
        _goalTargetController.text = _trimNum(habit.goalTarget!);
      }
      _goalUnitController.text = habit.goalUnit ?? '';
      _notesController.text = habit.notes ?? '';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _startDate = date);
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _endDate = date);
  }

  Future<void> _pickReminder() async {
    final time = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );
    if (time != null) setState(() => _reminderTime = time);
  }

  Future<void> _saveHabit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add a habit name',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final now = DateTime.now();
    DateTime? reminderDateTime;
    if (_reminderTime != null) {
      reminderDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        _reminderTime!.hour,
        _reminderTime!.minute,
      );
    }
    final goalTarget = double.tryParse(_goalTargetController.text.trim());
    final goalUnit = _goalUnitController.text.trim();
    final notes = _notesController.text.trim();

    final repo = ref.read(habitRepositoryProvider);
    String? newId;
    if (_isEditing) {
      await repo.updateHabit(
        widget.habitId!,
        title: title,
        subtitle: _subtitleController.text.trim(),
        category: _category,
        priority: _priority,
        frequencyType: _frequencyType,
        daysOfWeek: _frequencyType == 'specificDays' ? _selectedDays : null,
        intervalDays: _frequencyType == 'interval' ? _intervalDays : null,
        reminderTime: reminderDateTime,
        startDate: _startDate,
        endDate: _endDate,
        goalTarget: goalTarget,
        goalUnit: goalUnit.isEmpty ? null : goalUnit,
        notes: notes.isEmpty ? null : notes,
      );
    } else {
      newId = await repo.addHabit(
        title,
        subtitle: _subtitleController.text.trim(),
        category: _category,
        priority: _priority,
        frequencyType: _frequencyType,
        daysOfWeek: _frequencyType == 'specificDays' ? _selectedDays : null,
        intervalDays: _frequencyType == 'interval' ? _intervalDays : null,
        reminderTime: reminderDateTime,
        startDate: _startDate,
        endDate: _endDate,
        goalTarget: goalTarget,
        goalUnit: goalUnit.isEmpty ? null : goalUnit,
        notes: notes.isEmpty ? null : notes,
      );
    }

    // Ensure the habits list refreshes immediately after save.
    ref.invalidate(habitsStreamProvider);
    final checkId = _isEditing ? widget.habitId! : (newId ?? '');
    if (reminderDateTime != null && checkId.isNotEmpty) {
      var nextReminder = reminderDateTime;
      if (!nextReminder.isAfter(DateTime.now())) {
        nextReminder = nextReminder.add(const Duration(days: 1));
      }
      await NotificationService().cancelReminder(checkId.hashCode);
      await NotificationService().scheduleReminder(
        checkId.hashCode,
        title,
        'Habit reminder',
        nextReminder,
        repeatComponents: DateTimeComponents.time,
      );
    }
    try {
      final saved = await ref
          .read(habitRepositoryProvider)
          .getHabitById(checkId);
      debugPrint(
        'QuietNote: saved habit check id=$checkId exists=${saved != null}',
      );
    } catch (e) {
      debugPrint('QuietNote: error verifying saved habit: $e');
    }

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/habits');
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the list, even when the form is empty/invalid.
  void _goBack() {
    context.canPop() ? context.pop() : context.go('/habits');
  }

  Future<void> _deleteHabit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete habit?'),
        content: const Text(
          'This removes the habit and its whole completion history. This can\'t be undone.',
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
      await NotificationService().cancelReminder(widget.habitId!.hashCode);
      await ref.read(habitRepositoryProvider).deleteHabit(widget.habitId!);
      if (!mounted) return;
      context.go('/habits');
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
        title: _isEditing ? 'Edit Habit' : 'New Habit',
        subtitle: _isEditing
            ? habitFrequencyLabel(
                _frequencyType,
                _selectedDays.isEmpty ? null : _selectedDays.join(','),
                _intervalDays,
              )
            : null,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteHabit,
              tooltip: 'Delete habit',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveHabit,
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
                    hintText: 'Habit name (e.g. Read 10 pages)',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                UiInput(
                  controller: _subtitleController,
                  hintText: 'Why are you doing this? (optional)',
                ),
                const SizedBox(height: 20),
                Text('Category', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: habitCategoryNames.map((name) {
                    final selected = name == _category;
                    final color = habitCategoryColor(context, name);
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
                              habitCategoryIcon(name),
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
                  options: habitPriorityOptions,
                ),
                const SizedBox(height: 20),
                Text('Frequency', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                UiToggleGroup<String>(
                  variant: UiToggleGroupVariant.segmented,
                  expand: true,
                  value: _frequencyType,
                  onChanged: (v) => setState(() => _frequencyType = v),
                  options: const [
                    UiToggleOption(value: 'daily', label: 'Daily'),
                    UiToggleOption(value: 'specificDays', label: 'Days'),
                    UiToggleOption(value: 'interval', label: 'Interval'),
                  ],
                ),
                if (_frequencyType == 'specificDays') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _weekdayShort.asMap().entries.map((e) {
                      final isSelected = _selectedDays.contains(e.key);
                      return FilterChip(
                        label: Text(e.value),
                        selected: isSelected,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedDays.add(e.key);
                            } else {
                              _selectedDays.remove(e.key);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
                if (_frequencyType == 'interval') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        'Every $_intervalDays days',
                        style: context.uiText.body,
                      ),
                      Expanded(
                        child: Slider(
                          value: _intervalDays.toDouble(),
                          min: 2,
                          max: 14,
                          divisions: 12,
                          onChanged: (val) =>
                              setState(() => _intervalDays = val.toInt()),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Text('Daily goal', style: context.uiText.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  'Optional — track a quantity instead of just done/not done.',
                  style: context.uiText.caption,
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: UiField(
                        label: 'At least',
                        child: UiInput(
                          controller: _goalTargetController,
                          hintText: '3',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          leadingIcon: Icons.track_changes_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: UiField(
                        label: 'Unit',
                        child: UiInput(
                          controller: _goalUnitController,
                          hintText: 'miles, pages, glasses...',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Start date', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                UiButton(
                  label: DateFormat.yMMMd().format(_startDate),
                  variant: UiVariant.outline,
                  leadingIcon: Icons.event_outlined,
                  onPressed: _pickStartDate,
                ),
                const SizedBox(height: 20),
                Text('End date', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                if (_endDate == null)
                  UiButton(
                    label: 'Add end date',
                    variant: UiVariant.outline,
                    leadingIcon: Icons.event_busy_outlined,
                    onPressed: _pickEndDate,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: UiButton(
                          label: DateFormat.yMMMd().format(_endDate!),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.event_busy_outlined,
                          onPressed: _pickEndDate,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: c.foregroundMuted,
                        tooltip: 'Remove end date',
                        onPressed: () => setState(() => _endDate = null),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Text('Reminder', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                if (_reminderTime == null)
                  UiButton(
                    label: 'Add reminder',
                    variant: UiVariant.outline,
                    leadingIcon: Icons.notifications_outlined,
                    onPressed: _pickReminder,
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: UiButton(
                          label: _reminderTime!.format(context),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.notifications_outlined,
                          onPressed: _pickReminder,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        color: c.foregroundMuted,
                        tooltip: 'Remove reminder',
                        onPressed: () => setState(() => _reminderTime = null),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),
                Text('Notes', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                UiInput.multiline(
                  controller: _notesController,
                  hintText: 'Any extra detail, cues, or context...',
                  minLines: 3,
                  maxLines: 6,
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
