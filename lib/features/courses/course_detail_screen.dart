import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

class CourseDetailScreen extends ConsumerWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  Future<void> _confirmDeleteAssessment(
    BuildContext context,
    WidgetRef ref,
    Assessment assessment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete assessment?'),
        content: Text('This removes "${assessment.name}". This can\'t be undone.'),
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
      await ref.read(courseRepositoryProvider).deleteAssessment(assessment.id);
    }
  }

  Future<void> _openAssessmentEditor(
    BuildContext context,
    WidgetRef ref, {
    Assessment? assessment,
  }) {
    return UiDialog.show(
      context,
      child: _AssessmentEditorDialog(courseId: courseId, assessment: assessment),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final c = context.uiColors;

    return coursesAsync.when(
      data: (courses) {
        final course = courses.where((crs) => crs.id == courseId).firstOrNull;
        if (course == null) {
          return UiPage(
            header: UiHeader(
              leading: UiIconButton(
                icon: Icons.arrow_back,
                variant: UiVariant.ghost,
                onPressed: () => context.canPop() ? context.pop() : context.go('/courses'),
              ),
              title: 'Course',
            ),
            child: const UiEmptyState(
              title: 'Course not found',
              message: 'It may have been deleted.',
              icon: Icons.search_off_rounded,
            ),
          );
        }

        final assessmentsAsync = ref.watch(courseAssessmentsStreamProvider(courseId));
        final assessments = assessmentsAsync.value ?? const <Assessment>[];
        final average = weightedAverage(assessments);
        final hasTarget = course.targetGrade != null;
        final meetsTarget = !hasTarget || average >= course.targetGrade!;
        final intent = assessments.isEmpty
            ? UiIntent.neutral
            : (meetsTarget ? UiIntent.success : UiIntent.danger);

        return UiPage(
          header: UiHeader(
            leading: UiIconButton(
              icon: Icons.arrow_back,
              variant: UiVariant.ghost,
              onPressed: () => context.canPop() ? context.pop() : context.go('/courses'),
            ),
            title: course.name,
            actions: [
              UiIconButton(
                icon: Icons.edit_outlined,
                variant: UiVariant.ghost,
                tooltip: 'Edit course',
                onPressed: () => context.push('/courses/edit/${course.id}'),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: UiCard(
                      padding: const EdgeInsets.all(16),
                      accentColor: assessments.isEmpty ? null : intent.color(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Weighted average', style: context.uiText.caption),
                          const SizedBox(height: 4),
                          Text(
                            assessments.isEmpty ? '—' : '${average.toStringAsFixed(1)}%',
                            style: context.uiText.heading.copyWith(
                              color: assessments.isEmpty ? c.foregroundMuted : intent.color(context),
                            ),
                          ),
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
                          Text('Target', style: context.uiText.caption),
                          const SizedBox(height: 4),
                          Text(
                            hasTarget ? _trimNum(course.targetGrade!) : 'Not set',
                            style: context.uiText.heading,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Text('Assessments', style: context.uiText.bodyStrong),
                  const Spacer(),
                  UiButton(
                    label: 'Add',
                    leadingIcon: Icons.add,
                    size: UiSize.sm,
                    onPressed: () => _openAssessmentEditor(context, ref),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (assessments.isEmpty)
                const UiEmptyState(
                  title: 'No assessments yet',
                  message: 'Add a quiz, exam or assignment to start tracking this course.',
                  icon: Icons.fact_check_outlined,
                )
              else
                ...assessments.map(
                  (a) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AssessmentTile(
                      assessment: a,
                      onTap: () => _openAssessmentEditor(context, ref, assessment: a),
                      onDelete: () => _confirmDeleteAssessment(context, ref, a),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      loading: () => const Center(child: Padding(padding: EdgeInsets.only(top: 48), child: CircularProgressIndicator())),
      error: (err, stack) => UiPage(
        child: Text('Could not load course: $err', style: context.uiText.caption.copyWith(color: c.destructive)),
      ),
    );
  }

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment, required this.onTap, required this.onDelete});

  final Assessment assessment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.uiColors;
    final pct = assessment.maxScore == 0 ? 0.0 : (assessment.score / assessment.maxScore) * 100;
    return UiCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(assessment.name, style: context.uiText.bodyStrong),
                const SizedBox(height: 4),
                Text(
                  '${_trimNum(assessment.score)}/${_trimNum(assessment.maxScore)} \u00b7 weight ${_trimNum(assessment.weight)} \u00b7 ${DateFormat.yMMMd().format(assessment.date)}',
                  style: context.uiText.caption.copyWith(color: c.foregroundMuted),
                ),
              ],
            ),
          ),
          Text('${pct.toStringAsFixed(1)}%', style: context.uiText.bodyStrong),
          UiIconButton(
            icon: Icons.delete_outline,
            variant: UiVariant.ghost,
            size: UiSize.sm,
            tooltip: 'Delete assessment',
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _AssessmentEditorDialog extends ConsumerStatefulWidget {
  const _AssessmentEditorDialog({required this.courseId, this.assessment});

  final String courseId;
  final Assessment? assessment;

  @override
  ConsumerState<_AssessmentEditorDialog> createState() => _AssessmentEditorDialogState();
}

class _AssessmentEditorDialogState extends ConsumerState<_AssessmentEditorDialog> {
  late final _nameController = TextEditingController(text: widget.assessment?.name ?? '');
  late final _scoreController = TextEditingController(
    text: widget.assessment == null ? '' : _trimNum(widget.assessment!.score),
  );
  late final _maxScoreController = TextEditingController(
    text: widget.assessment == null ? '100' : _trimNum(widget.assessment!.maxScore),
  );
  late final _weightController = TextEditingController(
    text: widget.assessment == null ? '1' : _trimNum(widget.assessment!.weight),
  );
  late DateTime _date = widget.assessment?.date ?? DateTime.now();
  bool _isSaving = false;

  bool get _isEditing => widget.assessment != null;

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  void dispose() {
    _nameController.dispose();
    _scoreController.dispose();
    _maxScoreController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null) setState(() => _date = date);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final score = double.tryParse(_scoreController.text.trim());
    final maxScore = double.tryParse(_maxScoreController.text.trim());
    final weight = double.tryParse(_weightController.text.trim()) ?? 1.0;

    if (name.isEmpty || score == null || maxScore == null || maxScore == 0) {
      UiToast.show(
        context,
        title: 'Missing details',
        message: 'Add a name, score and a non-zero max score.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final repo = ref.read(courseRepositoryProvider);
    if (_isEditing) {
      await repo.updateAssessment(
        widget.assessment!.id,
        name: name,
        score: score,
        maxScore: maxScore,
        weight: weight,
        date: _date,
      );
    } else {
      await repo.addAssessment(
        widget.courseId,
        name,
        score: score,
        maxScore: maxScore,
        weight: weight,
        date: _date,
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return UiDialog(
      title: _isEditing ? 'Edit Assessment' : 'Add Assessment',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiField(
            label: 'Name',
            child: UiInput(controller: _nameController, hintText: 'e.g. Midterm exam', autofocus: !_isEditing),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: UiField(
                  label: 'Score',
                  child: UiInput(
                    controller: _scoreController,
                    hintText: '85',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UiField(
                  label: 'Out of',
                  child: UiInput(
                    controller: _maxScoreController,
                    hintText: '100',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: UiField(
                  label: 'Weight',
                  child: UiInput(
                    controller: _weightController,
                    hintText: '1',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: UiField(
                  label: 'Date',
                  child: UiButton(
                    label: DateFormat.yMMMd().format(_date),
                    variant: UiVariant.outline,
                    leadingIcon: Icons.event_outlined,
                    onPressed: _pickDate,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        UiButton(
          label: 'Cancel',
          variant: UiVariant.secondary,
          expandOnMobile: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
        UiButton(
          label: 'Save',
          expandOnMobile: false,
          loading: _isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}
