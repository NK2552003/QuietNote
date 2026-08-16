import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/notifications/notification_service.dart';

const int _reminderNone = -1;
const String _recurNone = 'none';
const String _goalNone = '';

const List<UiOption<int>> _reminderOptions = [
  UiOption(value: _reminderNone, label: 'No reminder'),
  UiOption(value: 0, label: 'At start time'),
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
  UiOption(value: 'yearly', label: 'Yearly'),
];

/// Preset event categories. Each maps to one of the app's chart-series
/// colors so tags stay visually distinct and consistent with the rest of
/// the design system (nothing hardcoded outside the token palette).
const List<String> categoryNames = [
  'Work',
  'Personal',
  'Health',
  'Social',
  'Travel',
  'Study',
  'Finance',
  'Other',
];

const List<IconData> _categoryIcons = [
  Icons.work_outline_rounded,
  Icons.person_outline_rounded,
  Icons.favorite_outline_rounded,
  Icons.groups_outlined,
  Icons.flight_takeoff_rounded,
  Icons.school_outlined,
  Icons.savings_outlined,
  Icons.label_outline_rounded,
];

int categoryIndex(String? category) {
  if (category == null) return categoryNames.length - 1;
  final i = categoryNames.indexOf(category);
  return i == -1 ? categoryNames.length - 1 : i;
}

Color categoryColor(BuildContext context, String? category) {
  const series = UiPalette.series;
  return series[categoryIndex(category) % series.length];
}

IconData categoryIcon(String? category) =>
    _categoryIcons[categoryIndex(category)];

class CalendarEventEditorScreen extends ConsumerStatefulWidget {
  final String? eventId;
  final DateTime? initialDate;
  const CalendarEventEditorScreen({super.key, this.eventId, this.initialDate});

  @override
  ConsumerState<CalendarEventEditorScreen> createState() =>
      _CalendarEventEditorScreenState();
}

class _CalendarEventEditorScreenState
    extends ConsumerState<CalendarEventEditorScreen> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  bool get _isEditing => widget.eventId != null;

  bool _isLoading = false;
  bool _isSaving = false;

  late DateTime _startDate;
  late DateTime _endDate;
  bool _isAllDay = false;
  String _category = categoryNames.first;
  int _reminderSel = _reminderNone;
  String _recurrenceSel = _recurNone;
  String _linkedGoalSel = _goalNone;
  String _linkedCourseSel = '';

  @override
  void initState() {
    super.initState();
    final base = widget.initialDate ?? DateTime.now();
    _startDate = DateTime(
      base.year,
      base.month,
      base.day,
      DateTime.now().hour,
      0,
    );
    _endDate = _startDate.add(const Duration(hours: 1));
    if (_isEditing) _loadEvent();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _loadEvent() async {
    setState(() => _isLoading = true);
    final event = await ref
        .read(calendarRepositoryProvider)
        .getEventById(widget.eventId!);
    if (event != null && mounted) {
      _titleController.text = event.title;
      _descController.text = event.description ?? '';
      _startDate = event.startTime;
      _endDate = event.endTime;
      _isAllDay = event.isAllDay;
      _category = event.category ?? categoryNames.first;
      _reminderSel = event.reminderOffset ?? _reminderNone;
      _recurrenceSel = event.recurrenceRule ?? _recurNone;
      _linkedGoalSel = event.linkedGoalId ?? _goalNone;
      _linkedCourseSel = event.courseId ?? '';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String? get _headerSubtitle {
    if (!_isEditing) return null;
    if (_isAllDay) return DateFormat.yMMMd().format(_startDate);
    return '${DateFormat.yMMMd().add_jm().format(_startDate)} – ${DateFormat.jm().format(_endDate)}';
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(() {
      final duration = _endDate.difference(_startDate);
      _startDate = DateTime(
        date.year,
        date.month,
        date.day,
        _startDate.hour,
        _startDate.minute,
      );
      if (!_endDate.isAfter(_startDate)) {
        _endDate = _startDate.add(
          duration.isNegative ? const Duration(hours: 1) : duration,
        );
      }
    });
  }

  Future<void> _pickStartTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startDate),
    );
    if (time == null) return;
    setState(() {
      final duration = _endDate.difference(_startDate);
      _startDate = DateTime(
        _startDate.year,
        _startDate.month,
        _startDate.day,
        time.hour,
        time.minute,
      );
      _endDate = _startDate.add(
        duration.isNegative ? const Duration(hours: 1) : duration,
      );
    });
  }

  Future<void> _pickEndDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _endDate.isBefore(_startDate) ? _startDate : _endDate,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    setState(
      () => _endDate = DateTime(
        date.year,
        date.month,
        date.day,
        _endDate.hour,
        _endDate.minute,
      ),
    );
  }

  Future<void> _pickEndTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_endDate),
    );
    if (time == null) return;
    setState(
      () => _endDate = DateTime(
        _endDate.year,
        _endDate.month,
        _endDate.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _saveEvent() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add an event name',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final description = _descController.text.trim();
    var endTime = _endDate;
    if (!endTime.isAfter(_startDate)) {
      endTime = _startDate.add(const Duration(hours: 1));
    }
    final reminderOffset = _reminderSel == _reminderNone ? null : _reminderSel;
    final recurrenceRule = _recurrenceSel == _recurNone ? null : _recurrenceSel;
    final linkedGoalId = _linkedGoalSel.isEmpty ? null : _linkedGoalSel;
    final linkedCourseId = _linkedCourseSel.isEmpty ? null : _linkedCourseSel;
    final color = categoryColor(context, _category).toARGB32();

    late final String eventId;
    if (_isEditing) {
      eventId = widget.eventId!;
      await ref
          .read(calendarRepositoryProvider)
          .updateEvent(
            eventId,
            title: title,
            startTime: _startDate,
            endTime: endTime,
            description: description.isEmpty ? null : description,
            isAllDay: _isAllDay,
            color: color,
            category: _category,
            recurrenceRule: recurrenceRule,
            reminderOffset: reminderOffset,
            linkedGoalId: linkedGoalId,
            courseId: linkedCourseId,
          );
    } else {
      eventId = await ref
          .read(calendarRepositoryProvider)
          .addEvent(
            title,
            _startDate,
            endTime,
            description: description.isEmpty ? null : description,
            isAllDay: _isAllDay,
            color: color,
            category: _category,
            recurrenceRule: recurrenceRule,
            reminderOffset: reminderOffset,
            linkedGoalId: linkedGoalId,
            courseId: linkedCourseId,
          );
    }

    if (!_isAllDay && reminderOffset != null) {
      final scheduledTime = _startDate.subtract(
        Duration(minutes: reminderOffset),
      );
      if (scheduledTime.isAfter(DateTime.now())) {
        final scheduled = await NotificationService().scheduleReminder(
          eventId.hashCode,
          title,
          description.isEmpty ? 'Event reminder' : description,
          scheduledTime,
          repeatComponents: _repeatComponent(recurrenceRule),
        );
        if (!scheduled && mounted) {
          UiToast.show(
            context,
            title: 'Event saved without a reminder',
            message:
                'Enable notification permission in Settings to receive it.',
            intent: UiIntent.warning,
          );
        }
      }
    }

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/calendar');
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the calendar, even when the form is empty/invalid.
  void _goBack() {
    context.canPop() ? context.pop() : context.go('/calendar');
  }

  DateTimeComponents? _repeatComponent(String? rule) => switch (rule) {
    'daily' => DateTimeComponents.time,
    'weekly' => DateTimeComponents.dayOfWeekAndTime,
    'monthly' => DateTimeComponents.dayOfMonthAndTime,
    'yearly' => DateTimeComponents.dateAndTime,
    _ => null,
  };

  Future<void> _deleteEvent() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete event?'),
        content: const Text('This removes the event. This can\'t be undone.'),
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
      await NotificationService().cancelReminder(widget.eventId!.hashCode);
      await ref.read(calendarRepositoryProvider).deleteEvent(widget.eventId!);
      if (!mounted) return;
      context.canPop() ? context.pop() : context.go('/calendar');
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
        title: _isEditing ? 'Edit Event' : 'New Event',
        subtitle: _headerSubtitle,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteEvent,
              tooltip: 'Delete event',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveEvent,
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
                    hintText: 'Event title',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                UiTextarea(
                  controller: _descController,
                  label: 'Description',
                  hintText: 'Add notes, agenda, or a location...',
                  rows: 3,
                  maxRows: 6,
                  showCounter: false,
                ),
                const SizedBox(height: 20),
                Text('Category', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: categoryNames.map((name) {
                    final selected = name == _category;
                    final color = categoryColor(context, name);
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
                              categoryIcon(name),
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
                UiSwitch(
                  asCard: true,
                  label: 'All day',
                  description: 'No specific start or end time',
                  value: _isAllDay,
                  onChanged: (v) => setState(() => _isAllDay = v),
                ),
                const SizedBox(height: 16),
                Text('Starts', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: UiButton(
                        label: DateFormat.yMMMd().format(_startDate),
                        variant: UiVariant.outline,
                        leadingIcon: Icons.event_outlined,
                        onPressed: _pickStartDate,
                      ),
                    ),
                    if (!_isAllDay) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: UiButton(
                          label: DateFormat.jm().format(_startDate),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.schedule_outlined,
                          onPressed: _pickStartTime,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                Text('Ends', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: UiButton(
                        label: DateFormat.yMMMd().format(_endDate),
                        variant: UiVariant.outline,
                        leadingIcon: Icons.event_outlined,
                        onPressed: _pickEndDate,
                      ),
                    ),
                    if (!_isAllDay) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: UiButton(
                          label: DateFormat.jm().format(_endDate),
                          variant: UiVariant.outline,
                          leadingIcon: Icons.schedule_outlined,
                          onPressed: _pickEndTime,
                        ),
                      ),
                    ],
                  ],
                ),
                if (!_isAllDay) ...[
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
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
