import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

class CourseDetailScreen extends ConsumerStatefulWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
      child: _AssessmentEditorDialog(courseId: widget.courseId, assessment: assessment),
    );
  }

  Future<void> _quickAddTask(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Course Task'),
        content: TextField(
          controller: titleController,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Read Chapter 4 & finish problem set',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok == true && titleController.text.trim().isNotEmpty) {
      await ref.read(taskRepositoryProvider).addTask(
            titleController.text.trim(),
            courseId: widget.courseId,
          );
      if (context.mounted) {
        UiToast.show(context, title: 'Task added', intent: UiIntent.success);
      }
    }
  }

  Future<void> _quickAddNote(BuildContext context, WidgetRef ref) async {
    final titleController = TextEditingController();
    final contentController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Lecture Note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Note title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: contentController,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Lecture key takeaways...'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save Note')),
        ],
      ),
    );
    if (ok == true && titleController.text.trim().isNotEmpty) {
      await ref.read(noteRepositoryProvider).addNote(
            titleController.text.trim(),
            contentController.text.trim(),
            courseId: widget.courseId,
          );
      if (context.mounted) {
        UiToast.show(context, title: 'Note created', intent: UiIntent.success);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesStreamProvider);
    final c = context.uiColors;

    return coursesAsync.when(
      data: (courses) {
        final course = courses.where((crs) => crs.id == widget.courseId).firstOrNull;
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

        final accentColor = course.color != null ? Color(course.color!) : c.primary;

        return UiPage(
          header: UiHeader(
            leading: UiIconButton(
              icon: Icons.arrow_back,
              variant: UiVariant.ghost,
              onPressed: () => context.canPop() ? context.pop() : context.go('/courses'),
            ),
            title: course.code != null && course.code!.isNotEmpty
                ? '${course.code} \u2014 ${course.name}'
                : course.name,
            subtitle: [
              if (course.instructor != null) 'Prof. ${course.instructor}',
              if (course.room != null) course.room,
              if (course.term != null) course.term,
            ].join(' \u00b7 '),
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
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: accentColor,
                unselectedLabelColor: c.foregroundMuted,
                indicatorColor: accentColor,
                tabs: const [
                  Tab(text: 'Grades & Overview'),
                  Tab(text: 'Tasks & Homework'),
                  Tab(text: 'Notes'),
                  Tab(text: 'Classes & Exams'),
                  Tab(text: 'Study Focus'),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.65,
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _GradesTab(
                      course: course,
                      courseId: widget.courseId,
                      onAddAssessment: () => _openAssessmentEditor(context, ref),
                      onEditAssessment: (a) => _openAssessmentEditor(context, ref, assessment: a),
                      onDeleteAssessment: (a) => _confirmDeleteAssessment(context, ref, a),
                    ),
                    _TasksTab(
                      courseId: widget.courseId,
                      onAddTask: () => _quickAddTask(context, ref),
                    ),
                    _NotesTab(
                      courseId: widget.courseId,
                      onAddNote: () => _quickAddNote(context, ref),
                    ),
                    _EventsTab(courseId: widget.courseId),
                    _FocusTab(courseId: widget.courseId, courseName: course.name),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.only(top: 48), child: CircularProgressIndicator()),
      ),
      error: (err, stack) => UiPage(
        child: Text(
          'Could not load course: $err',
          style: context.uiText.caption.copyWith(color: c.destructive),
        ),
      ),
    );
  }
}

class _GradesTab extends ConsumerWidget {
  const _GradesTab({
    required this.course,
    required this.courseId,
    required this.onAddAssessment,
    required this.onEditAssessment,
    required this.onDeleteAssessment,
  });

  final Course course;
  final String courseId;
  final VoidCallback onAddAssessment;
  final ValueChanged<Assessment> onEditAssessment;
  final ValueChanged<Assessment> onDeleteAssessment;

  String _trimNum(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final assessmentsAsync = ref.watch(courseAssessmentsStreamProvider(courseId));
    final assessments = assessmentsAsync.value ?? const <Assessment>[];
    final average = weightedAverage(assessments);
    final hasTarget = course.targetGrade != null;
    final meetsTarget = !hasTarget || average >= course.targetGrade!;
    final intent = assessments.isEmpty
        ? UiIntent.neutral
        : (meetsTarget ? UiIntent.success : UiIntent.danger);

    return SingleChildScrollView(
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
                      Text('Target grade', style: context.uiText.caption),
                      const SizedBox(height: 4),
                      Text(
                        hasTarget ? '${_trimNum(course.targetGrade!)}%' : 'Not set',
                        style: context.uiText.heading,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (course.notes != null && course.notes!.isNotEmpty) ...[
            const SizedBox(height: 14),
            UiCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: c.primary),
                      const SizedBox(width: 8),
                      Text('Syllabus & Info', style: context.uiText.bodyStrong),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(course.notes!, style: context.uiText.body),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Assessments (${assessments.length})', style: context.uiText.bodyStrong),
              const Spacer(),
              UiButton(
                label: 'Add Assessment',
                leadingIcon: Icons.add,
                size: UiSize.sm,
                onPressed: onAddAssessment,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (assessments.isEmpty)
            const UiEmptyState(
              title: 'No assessments yet',
              message: 'Add a quiz, exam or assignment to track grades for this course.',
              icon: Icons.fact_check_outlined,
            )
          else
            ...assessments.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AssessmentTile(
                  assessment: a,
                  onTap: () => onEditAssessment(a),
                  onDelete: () => onDeleteAssessment(a),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TasksTab extends ConsumerWidget {
  const _TasksTab({required this.courseId, required this.onAddTask});
  final String courseId;
  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(courseTasksStreamProvider(courseId));
    final tasks = tasksAsync.value ?? const <Task>[];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Linked Homework & Tasks (${tasks.length})', style: context.uiText.bodyStrong),
              const Spacer(),
              UiButton(
                label: 'Add Task',
                leadingIcon: Icons.add,
                size: UiSize.sm,
                onPressed: onAddTask,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (tasks.isEmpty)
            const UiEmptyState(
              title: 'No course tasks',
              message: 'Tasks created for this course will show up here.',
              icon: Icons.checklist_outlined,
            )
          else
            ...tasks.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiCard(
                  onTap: () => ref.read(taskRepositoryProvider).toggleTaskCompletion(t.id, t.isCompleted),
                  child: Row(
                    children: [
                      Icon(
                        t.isCompleted ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: context.uiColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t.title,
                          style: context.uiText.bodyStrong.copyWith(
                            decoration: t.isCompleted ? TextDecoration.lineThrough : null,
                          ),
                        ),
                      ),
                      if (t.dueDate != null)
                        UiBadge(
                          label: DateFormat.MMMd().format(t.dueDate!),
                          intent: UiIntent.neutral,
                          size: UiSize.xs,
                        ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.courseId, required this.onAddNote});
  final String courseId;
  final VoidCallback onAddNote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(courseNotesStreamProvider(courseId));
    final notes = notesAsync.value ?? const <Note>[];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Course Lecture Notes (${notes.length})', style: context.uiText.bodyStrong),
              const Spacer(),
              UiButton(
                label: 'Add Note',
                leadingIcon: Icons.add,
                size: UiSize.sm,
                onPressed: onAddNote,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (notes.isEmpty)
            const UiEmptyState(
              title: 'No notes yet',
              message: 'Notes tagged with this course will be collected here.',
              icon: Icons.notes_outlined,
            )
          else
            ...notes.map(
              (n) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiCard(
                  onTap: () => context.push('/notes/${n.id}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, style: context.uiText.bodyStrong),
                      const SizedBox(height: 4),
                      Text(
                        n.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: context.uiText.caption.copyWith(color: context.uiColors.foregroundMuted),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        DateFormat.yMMMd().format(n.createdAt),
                        style: context.uiText.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EventsTab extends ConsumerWidget {
  const _EventsTab({required this.courseId});
  final String courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(courseEventsStreamProvider(courseId));
    final events = eventsAsync.value ?? const <CalendarEvent>[];
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Classes & Exams (${events.length})', style: context.uiText.bodyStrong),
              const Spacer(),
              UiButton(
                label: 'Schedule Event',
                leadingIcon: Icons.calendar_month_outlined,
                size: UiSize.sm,
                onPressed: () => context.push('/calendar/new'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (events.isEmpty)
            const UiEmptyState(
              title: 'No classes or exams scheduled',
              message: 'Add calendar events linked to this course.',
              icon: Icons.event_outlined,
            )
          else
            ...events.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiCard(
                  onTap: () => context.push('/calendar/${e.id}'),
                  child: Row(
                    children: [
                      Icon(Icons.event_outlined, color: context.uiColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(e.title, style: context.uiText.bodyStrong),
                            Text(
                              '${DateFormat.yMMMd().format(e.startTime)} \u00b7 ${DateFormat.jm().format(e.startTime)}',
                              style: context.uiText.caption,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FocusTab extends ConsumerWidget {
  const _FocusTab({required this.courseId, required this.courseName});
  final String courseId;
  final String courseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(courseFocusSessionsStreamProvider(courseId));
    final sessions = sessionsAsync.value ?? const <FocusSession>[];
    final totalMinutes = sessions
        .where((s) => s.status == 'completed')
        .fold<int>(0, (sum, s) => sum + s.durationMinutes);
    final hours = (totalMinutes / 60).toStringAsFixed(1);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          UiCard(
            accentColor: context.uiColors.primary,
            child: Row(
              children: [
                Icon(Icons.timer_outlined, size: 36, color: context.uiColors.primary),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$hours Study Hours Logged', style: context.uiText.heading),
                    Text('${sessions.length} total study sessions', style: context.uiText.caption),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: UiButton(
              label: 'Start Focus Session for $courseName',
              leadingIcon: Icons.play_arrow_rounded,
              onPressed: () => context.go('/clock'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Focus Session History', style: context.uiText.bodyStrong),
          const SizedBox(height: 10),
          if (sessions.isEmpty)
            const UiEmptyState(
              title: 'No focus sessions logged',
              message: 'Time your study sessions on the Clock screen to track your progress here.',
              icon: Icons.hourglass_empty_outlined,
            )
          else
            ...sessions.map(
              (s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: UiCard(
                  child: Row(
                    children: [
                      Icon(Icons.check_circle_outline, color: context.uiColors.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.durationMinutes} min focus session', style: context.uiText.bodyStrong),
                            Text(
                              DateFormat.yMMMd().add_jm().format(s.startedAt),
                              style: context.uiText.caption,
                            ),
                            if (s.reflection != null && s.reflection!.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text('"${s.reflection}"', style: context.uiText.caption.copyWith(fontStyle: FontStyle.italic)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
