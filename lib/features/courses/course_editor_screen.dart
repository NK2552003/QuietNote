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
  final _codeController = TextEditingController();
  final _targetController = TextEditingController();
  final _instructorController = TextEditingController();
  final _roomController = TextEditingController();
  final _termController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _notesController = TextEditingController();
  int? _selectedColor = 0xFF4F46E5; // Default Indigo

  bool get _isEditing => widget.courseId != null;

  bool _isLoading = false;
  bool _isSaving = false;

  static const List<int> _colorPresets = [
    0xFF4F46E5, // Indigo
    0xFF10B981, // Emerald
    0xFF8B5CF6, // Purple
    0xFFF43F5E, // Rose
    0xFFF59E0B, // Amber
    0xFF06B6D4, // Cyan
    0xFF64748B, // Slate
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) _loadCourse();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _targetController.dispose();
    _instructorController.dispose();
    _roomController.dispose();
    _termController.dispose();
    _scheduleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCourse() async {
    setState(() => _isLoading = true);
    final course = await ref
        .read(courseRepositoryProvider)
        .getCourseById(widget.courseId!);
    if (course != null && mounted) {
      _nameController.text = course.name;
      _codeController.text = course.code ?? '';
      _instructorController.text = course.instructor ?? '';
      _roomController.text = course.room ?? '';
      _termController.text = course.term ?? '';
      _scheduleController.text = course.schedule ?? '';
      _notesController.text = course.notes ?? '';
      _selectedColor = course.color ?? 0xFF4F46E5;
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
    final code = _codeController.text.trim().isEmpty ? null : _codeController.text.trim();
    final instructor = _instructorController.text.trim().isEmpty ? null : _instructorController.text.trim();
    final room = _roomController.text.trim().isEmpty ? null : _roomController.text.trim();
    final term = _termController.text.trim().isEmpty ? null : _termController.text.trim();
    final schedule = _scheduleController.text.trim().isEmpty ? null : _scheduleController.text.trim();
    final notes = _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

    late final String courseId;
    if (_isEditing) {
      courseId = widget.courseId!;
      await ref.read(courseRepositoryProvider).updateCourse(
            courseId,
            name: name,
            targetGrade: target,
            code: code,
            instructor: instructor,
            room: room,
            color: _selectedColor,
            schedule: schedule,
            term: term,
            notes: notes,
          );
    } else {
      courseId = await ref.read(courseRepositoryProvider).addCourse(
            name,
            targetGrade: target,
            code: code,
            instructor: instructor,
            room: room,
            color: _selectedColor,
            schedule: schedule,
            term: term,
            notes: notes,
          );
    }

    if (!mounted) return;
    context.canPop() ? context.pop() : context.go('/courses');
  }

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
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _nameController,
                    autofocus: !_isEditing,
                    style: context.uiText.heading,
                    decoration: InputDecoration.collapsed(
                      hintText: 'Course name (e.g. Computer Science)',
                      hintStyle: context.uiText.heading.copyWith(
                        color: c.foregroundMuted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: UiField(
                          label: 'Course code',
                          child: UiInput(
                            controller: _codeController,
                            hintText: 'e.g. CS101',
                            leadingIcon: Icons.tag,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: UiField(
                          label: 'Target grade',
                          child: UiInput(
                            controller: _targetController,
                            hintText: 'e.g. 90',
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            leadingIcon: Icons.flag_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: UiField(
                          label: 'Instructor',
                          child: UiInput(
                            controller: _instructorController,
                            hintText: 'e.g. Dr. Alan Turing',
                            leadingIcon: Icons.person_outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: UiField(
                          label: 'Location / Room',
                          child: UiInput(
                            controller: _roomController,
                            hintText: 'e.g. Hall B, Room 302',
                            leadingIcon: Icons.location_on_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: UiField(
                          label: 'Term / Semester',
                          child: UiInput(
                            controller: _termController,
                            hintText: 'e.g. Fall 2026',
                            leadingIcon: Icons.school_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: UiField(
                          label: 'Class schedule',
                          child: UiInput(
                            controller: _scheduleController,
                            hintText: 'e.g. Mon/Wed 10 AM',
                            leadingIcon: Icons.access_time_outlined,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('Course theme color', style: context.uiText.bodyStrong),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    children: _colorPresets.map((colorVal) {
                      final selected = _selectedColor == colorVal;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedColor = colorVal),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(colorVal),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? c.foreground : Colors.transparent,
                              width: 2.5,
                            ),
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 20, color: Colors.white)
                              : null,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  UiField(
                    label: 'Syllabus & Course notes',
                    child: UiInput(
                      controller: _notesController,
                      hintText: 'Grading scheme, professor office hours, policies...',
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
