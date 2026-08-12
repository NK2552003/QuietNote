import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/features/habits/habit_editor_screen.dart' show habitCategoryNames;
import 'package:quietnote/features/goals/goal_editor_screen.dart' show goalCategoryNames;

import 'capture_parser.dart';
import 'capture_actions.dart';

const List<UiToggleOption<String>> _moodToggleOptions = [
  UiToggleOption(value: 'Great', label: '😃 Great'),
  UiToggleOption(value: 'Neutral', label: '😐 Neutral'),
  UiToggleOption(value: 'Bad', label: '😔 Bad'),
];

const List<UiToggleOption<int>> _priorityToggleOptions = [
  UiToggleOption(value: 0, label: 'None'),
  UiToggleOption(value: 1, label: 'Low', intent: UiIntent.info),
  UiToggleOption(value: 2, label: 'Medium', intent: UiIntent.warning),
  UiToggleOption(value: 3, label: 'High', intent: UiIntent.danger),
];

const List<UiToggleOption<String>> _frequencyToggleOptions = [
  UiToggleOption(value: 'daily', label: 'Daily'),
  UiToggleOption(value: 'weekly', label: 'Weekly'),
];

/// Full editor for a single [CaptureDraft]. Presented inside [UiDialog.show]
/// (bottom sheet on phones, centered modal on larger screens) so it reads as
/// a natural continuation of the capture composer rather than a new page.
class CaptureReviewSheet extends ConsumerStatefulWidget {
  const CaptureReviewSheet({super.key, required this.initial});
  final CaptureDraft initial;

  @override
  ConsumerState<CaptureReviewSheet> createState() => _CaptureReviewSheetState();
}

class _CaptureReviewSheetState extends ConsumerState<CaptureReviewSheet> {
  late CaptureDraft _draft;
  late TextEditingController _titleCtrl;
  late TextEditingController _detailsCtrl;
  late TextEditingController _targetCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial.copy();
    _titleCtrl = TextEditingController(text: _draft.title);
    _detailsCtrl = TextEditingController(text: _draft.details);
    _targetCtrl = TextEditingController(text: _draft.goalTarget.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _detailsCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  void _changeType(CaptureType type) {
    setState(() => _draft.type = type);
  }

  Future<void> _pickDate({required bool isStart}) async {
    final base = (isStart ? _draft.startTime : _draft.endTime) ??
        _draft.dueDate ??
        DateTime.now().add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(base));
    if (!mounted) return;
    final merged = DateTime(date.year, date.month, date.day, time?.hour ?? base.hour, time?.minute ?? base.minute);
    setState(() {
      if (_draft.type == CaptureType.event) {
        if (isStart) {
          _draft.startTime = merged;
          if (_draft.endTime == null || _draft.endTime!.isBefore(merged)) {
            _draft.endTime = merged.add(const Duration(hours: 1));
          }
        } else {
          _draft.endTime = merged;
        }
      } else {
        _draft.dueDate = merged;
      }
    });
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      _draft.title = title;
      _draft.details = _detailsCtrl.text.trim();
      _draft.goalTarget = double.tryParse(_targetCtrl.text.trim()) ?? _draft.goalTarget;
      final result = await saveCaptureDraft(ref, _draft);

      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      UiToast.show(
        context,
        title: 'Could not save capture',
        message: '$e',
        intent: UiIntent.danger,
        icon: Icons.error_outline,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final dateFmt = DateFormat('EEE, MMM d · h:mm a');

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(_draft.type.icon, color: c.primary, size: context.uiSizes.iconMd),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Review capture', style: context.uiText.title),
              ),
              UiIconButton(
                icon: Icons.close,
                variant: UiVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Confirm the type and details before saving.',
            style: context.uiText.caption.copyWith(color: c.foregroundMuted),
          ),
          const SizedBox(height: 16),
          Text('Save as', style: context.uiText.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in CaptureType.values)
                _TypeChip(
                  type: type,
                  selected: _draft.type == type,
                  onTap: () => _changeType(type),
                ),
            ],
          ),
          const SizedBox(height: 20),
          UiField(
            label: 'Title',
            required: true,
            child: UiInput(controller: _titleCtrl, hintText: 'What is this about?'),
          ),
          const SizedBox(height: 16),
          if (_draft.type != CaptureType.journal) ...[
            UiField(
              label: _draft.type == CaptureType.note ? 'Content' : 'Details',
              child: UiTextarea(controller: _detailsCtrl, hintText: 'Add more detail (optional)', rows: 3),
            ),
            const SizedBox(height: 16),
          ],
          if (_draft.type == CaptureType.journal) ...[
            UiField(
              label: 'Entry',
              required: true,
              child: UiTextarea(controller: _detailsCtrl, hintText: 'How was it?', rows: 5),
            ),
            const SizedBox(height: 16),
            Text('Mood', style: context.uiText.label),
            const SizedBox(height: 8),
            UiToggleGroup<String>(
              options: _moodToggleOptions,
              value: _draft.mood,
              onChanged: (v) => setState(() => _draft.mood = v),
            ),
            const SizedBox(height: 16),
          ],
          if (_draft.type == CaptureType.todo) ...[
            Text('Priority', style: context.uiText.label),
            const SizedBox(height: 8),
            UiToggleGroup<int>(
              options: _priorityToggleOptions,
              value: _draft.priority,
              onChanged: (v) => setState(() => _draft.priority = v),
            ),
            const SizedBox(height: 16),
            _DatePickRow(
              label: _draft.dueDate == null ? 'Add due date' : dateFmt.format(_draft.dueDate!),
              icon: Icons.event_outlined,
              onTap: () => _pickDate(isStart: true),
              onClear: _draft.dueDate == null ? null : () => setState(() => _draft.dueDate = null),
            ),
            const SizedBox(height: 8),
          ],
          if (_draft.type == CaptureType.event) ...[
            _DatePickRow(
              label: 'Starts · ${dateFmt.format(_draft.startTime ?? DateTime.now().add(const Duration(hours: 1)))}',
              icon: Icons.play_circle_outline,
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 8),
            _DatePickRow(
              label: 'Ends · ${dateFmt.format(_draft.endTime ?? (_draft.startTime ?? DateTime.now()).add(const Duration(hours: 1)))}',
              icon: Icons.stop_circle_outlined,
              onTap: () => _pickDate(isStart: false),
            ),
            const SizedBox(height: 8),
          ],
          if (_draft.type == CaptureType.habit) ...[
            Text('Category', style: context.uiText.label),
            const SizedBox(height: 8),
            UiSelect<String>(
              value: _draft.category,
              options: [for (final cat in habitCategoryNames) UiOption(value: cat, label: cat)],
              onChanged: (v) => setState(() => _draft.category = v),
            ),
            const SizedBox(height: 16),
            Text('Frequency', style: context.uiText.label),
            const SizedBox(height: 8),
            UiToggleGroup<String>(
              options: _frequencyToggleOptions,
              value: _draft.frequencyType,
              onChanged: (v) => setState(() => _draft.frequencyType = v),
            ),
            const SizedBox(height: 8),
          ],
          if (_draft.type == CaptureType.goal) ...[
            UiField(
              label: 'Target',
              child: UiInput(
                controller: _targetCtrl,
                keyboardType: TextInputType.number,
                hintText: 'e.g. 100',
              ),
            ),
            const SizedBox(height: 16),
            Text('Category', style: context.uiText.label),
            const SizedBox(height: 8),
            UiSelect<String>(
              value: _draft.category,
              options: [for (final cat in goalCategoryNames) UiOption(value: cat, label: cat)],
              onChanged: (v) => setState(() => _draft.category = v),
            ),
            const SizedBox(height: 16),
            _DatePickRow(
              label: _draft.dueDate == null ? 'Add deadline' : dateFmt.format(_draft.dueDate!),
              icon: Icons.flag_outlined,
              onTap: () => _pickDate(isStart: true),
              onClear: _draft.dueDate == null ? null : () => setState(() => _draft.dueDate = null),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: UiButton(
                  label: 'Cancel',
                  variant: UiVariant.secondary,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UiButton(
                  label: 'Save',
                  loading: _isSaving,
                  leadingIcon: Icons.check,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type, required this.selected, required this.onTap});
  final CaptureType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary.withValues(alpha: 0.12) : c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? c.primary : c.border, width: selected ? 1.5 : 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(type.icon, size: 15, color: selected ? c.primary : c.foregroundMuted),
            const SizedBox(width: 6),
            Text(
              type.shortLabel,
              style: context.uiText.caption.copyWith(
                fontWeight: FontWeight.w700,
                color: selected ? c.primary : c.foregroundMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickRow extends StatelessWidget {
  const _DatePickRow({required this.label, required this.icon, required this.onTap, this.onClear});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surfaceMuted,
          borderRadius: BorderRadius.circular(context.uiRadii.lg),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: c.foregroundMuted),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: context.uiText.body)),
            if (onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Icon(Icons.close, size: 16, color: c.foregroundMuted),
              ),
          ],
        ),
      ),
    );
  }
}
