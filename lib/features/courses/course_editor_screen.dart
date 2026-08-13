import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';

class CourseEditorScreen extends ConsumerStatefulWidget {
  final String? courseId;
  const CourseEditorScreen({super.key, this.courseId});

  @override
  ConsumerState<CourseEditorScreen> createState() => _CourseEditorScreenState();
}

class _CourseEditorScreenState extends ConsumerState<CourseEditorScreen> {
  final _nameController = TextEditingController();
  final _targetController = TextEditingController();

  bool get _isEditing => widget.courseId != null;

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadCourse();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  Future<void> _loadCourse() async {
    setState(() => _isLoading = true);
    final course = await ref
        .read(courseRepositoryProvider)
        .getCourseById(widget.courseId!);
    if (course != null && mounted) {
      _nameController.text = course.name;
      if (course.targetGrade != null) {
        _targetController.text = _trimNum(course.targetGrade!);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  Future<void> _saveCourse() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      if (!mounted) return;
      UiToast.show(
        context,
        title: 'Add a course name',
        message: 'A name is required before you can save.',
        intent: UiIntent.warning,
      );
      return;
    }
    if (_isSaving) return;
    setState(() => _isSaving = true);

    final targetText = _targetController.text.trim();
    final target = targetText.isEmpty ? null : double.tryParse(targetText);

    late final String courseId;
    if (_isEditing) {
      courseId = widget.courseId!;
      await ref
          .read(courseRepositoryProvider)
          .updateCourse(courseId, name: name, targetGrade: target);
    } else {
      courseId = await ref
          .read(courseRepositoryProvider)
          .addCourse(name, targetGrade: target);
    }

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/courses');
  }

  /// Leaves the editor without saving. Used by the back arrow so it always
  /// returns to the list, even when the form is empty/invalid.
  void _goBack() {
    context.canPop() ? context.pop() : context.go('/courses');
  }

  Future<void> _deleteCourse() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete course?'),
        content: const Text(
          'This removes the course and every assessment logged under it. This can\'t be undone.',
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
      await ref.read(courseRepositoryProvider).deleteCourse(widget.courseId!);
      if (!mounted) return;
      context.canPop() ? context.pop() : context.go('/courses');
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
        title: _isEditing ? 'Edit Course' : 'New Course',
        actions: [
          if (_isEditing)
            UiIconButton(
              icon: Icons.delete_outline,
              variant: UiVariant.ghost,
              onPressed: _deleteCourse,
              tooltip: 'Delete course',
            ),
          UiButton(
            label: 'Save',
            leadingIcon: Icons.check,
            loading: _isSaving,
            onPressed: _saveCourse,
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
                  controller: _nameController,
                  autofocus: !_isEditing,
                  style: context.uiText.heading,
                  decoration: InputDecoration.collapsed(
                    hintText: 'Course name (e.g. Biology 101)',
                    hintStyle: context.uiText.heading.copyWith(
                      color: c.foregroundMuted,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                UiField(
                  label: 'Target grade (optional)',
                  helper:
                      'Percentage or GPA — whatever scale your assessments use.',
                  child: UiInput(
                    controller: _targetController,
                    hintText: 'e.g. 90',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    leadingIcon: Icons.flag_outlined,
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    );
  }
}
