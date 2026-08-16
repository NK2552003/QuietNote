import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/features/routines/routines_screen.dart';

class RoutineEditorScreen extends ConsumerStatefulWidget {
  final String? routineId;
  const RoutineEditorScreen({super.key, this.routineId});

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  final _titleController = TextEditingController();
  final _noteController = TextEditingController();
  final _stepController = TextEditingController();

  bool get _isEditing => widget.routineId != null;
  bool _isLoading = false;
  bool _isSaving = false;

  String _timeOfDay = routineTimeBlocks.first;
  bool _isActive = true;
  List<RoutineStep> _steps = [];

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadRoutine();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _stepController.dispose();
    super.dispose();
  }

  Future<void> _loadRoutine() async {
    setState(() => _isLoading = true);
    final routine = await ref
        .read(routineRepositoryProvider)
        .getRoutineById(widget.routineId!);
    if (routine != null && mounted) {
      _titleController.text = routine.title;
      _timeOfDay = routineTimeBlocks.contains(routine.timeOfDay)
          ? routine.timeOfDay
          : routineTimeBlocks.first;
      _isActive = routine.isActive;
      final content = RoutineContent.parse(routine.description);
      _noteController.text = content.note;
      _steps = content.steps;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _addStep() {
    final text = _stepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _steps.add(RoutineStep(title: text));
      _stepController.clear();
    });
  }

  void _removeStep(int index) => setState(() => _steps.removeAt(index));

  void _reorderStep(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _steps.length) return;
    setState(() {
      final item = _steps.removeAt(index);
      _steps.insert(newIndex, item);
    });
  }

  Future<void> _saveRoutine() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add a routine name',
        message: 'A title is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final content = RoutineContent(
      note: _noteController.text.trim(),
      steps: _steps,
    );
    final description = content.encode().isEmpty ? null : content.encode();

    if (_isEditing) {
      await ref
          .read(routineRepositoryProvider)
          .updateRoutine(
            widget.routineId!,
            title: title,
            timeOfDay: _timeOfDay,
            description: description,
          );
      await ref
          .read(routineRepositoryProvider)
          .toggleRoutineActive(widget.routineId!, _isActive);
    } else {
      final id = await ref
          .read(routineRepositoryProvider)
          .addRoutine(title, _timeOfDay, description: description);
      if (!_isActive) {
        await ref
            .read(routineRepositoryProvider)
            .toggleRoutineActive(id, false);
      }
    }

    // Refresh the routines list provider so the new/updated routine appears immediately.
    ref.invalidate(routinesStreamProvider);

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/routines');
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the list, even when the form is empty/invalid.
  void _goBack() {
    context.canPop() ? context.pop() : context.go('/routines');
  }

  Future<void> _deleteRoutine() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete routine?'),
        content: const Text(
          'This removes the routine and its steps. This can\'t be undone.',
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
      await ref
          .read(routineRepositoryProvider)
          .deleteRoutine(widget.routineId!);
      if (!mounted) return;
      context.canPop() ? context.pop() : context.go('/routines');
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
        title: _isEditing ? 'Edit Routine' : 'New Routine',
        subtitle: _isEditing ? (_isActive ? 'Active' : 'Paused') : null,
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteRoutine,
              tooltip: 'Delete routine',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveRoutine,
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
                    hintText: 'Routine name (e.g. Morning Workout)',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text('Time of day', style: context.uiText.bodyStrong),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: routineTimeBlocks.map((block) {
                    final selected = block == _timeOfDay;
                    final color = routineTimeColor(context, block);
                    return GestureDetector(
                      onTap: () => setState(() => _timeOfDay = block),
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
                              routineTimeIcon(block),
                              size: 15,
                              color: selected ? color : c.foregroundMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              block,
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
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  label: 'Active',
                  description: _isActive
                      ? 'This routine runs on schedule.'
                      : 'Paused — hidden from today\u2019s flow.',
                  asCard: true,
                ),
                const SizedBox(height: 20),
                UiField(
                  label: 'Description',
                  child: UiTextarea(
                    controller: _noteController,
                    hintText: 'What is this routine for?',
                    rows: 2,
                    maxRows: 4,
                    showCounter: false,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Steps', style: context.uiText.bodyStrong),
                    if (_steps.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        '${_steps.where((s) => s.isCompleted).length}/${_steps.length}',
                        style: context.uiText.caption,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Break the routine into an ordered checklist.',
                  style: context.uiText.caption,
                ),
                const SizedBox(height: 8),
                if (_steps.isNotEmpty)
                  ..._steps.asMap().entries.map((entry) {
                    final index = entry.key;
                    final step = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => setState(
                              () =>
                                  _steps[index].isCompleted = !step.isCompleted,
                            ),
                            child: Icon(
                              step.isCompleted
                                  ? Icons.check_box_rounded
                                  : Icons.check_box_outline_blank_rounded,
                              size: 20,
                              color: step.isCompleted
                                  ? c.primary
                                  : c.foregroundMuted,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step.title,
                              style: context.uiText.body.copyWith(
                                color: step.isCompleted
                                    ? c.foregroundMuted
                                    : null,
                                decoration: step.isCompleted
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
                                : () => _reorderStep(index, -1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.arrow_downward, size: 16),
                            color: c.foregroundMuted,
                            tooltip: 'Move down',
                            onPressed: index == _steps.length - 1
                                ? null
                                : () => _reorderStep(index, 1),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            color: c.foregroundMuted,
                            tooltip: 'Remove step',
                            onPressed: () => _removeStep(index),
                          ),
                        ],
                      ),
                    );
                  }),
                Row(
                  children: [
                    Expanded(
                      child: UiInput(
                        controller: _stepController,
                        hintText: 'Add a step...',
                        onSubmitted: (_) => _addStep(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    UiIconButton(
                      icon: Icons.add,
                      variant: UiVariant.outline,
                      onPressed: _addStep,
                      tooltip: 'Add step',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
