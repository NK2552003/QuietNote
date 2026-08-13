import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';
import 'package:quietnote/core/flutter-ui/flutter_ui.dart';

class CoursesScreen extends ConsumerWidget {
  const CoursesScreen({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Course course,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete course?'),
        content: Text(
          'This removes "${course.name}" and every assessment logged under it. This can\'t be undone.',
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
      await ref.read(courseRepositoryProvider).deleteCourse(course.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coursesAsync = ref.watch(coursesStreamProvider);

    return UiPage(
      header: const UiHeader(
        title: 'Courses',
        subtitle: 'Master new skills & expand your knowledge step by step.',
      ),
      floatingActionButton: UiFab(
        tooltip: 'New course',
        onPressed: () => context.push('/courses/new'),
      ),
      child: coursesAsync.when(
        loading: () => const _CoursesSkeleton(),
        error: (err, stack) => UiCard(
          accentColor: context.uiColors.destructive,
          child: Text(
            'Could not load courses: $err',
            style: context.uiText.caption.copyWith(
              color: context.uiColors.destructive,
            ),
          ),
        ),
        data: (courses) {
          if (courses.isEmpty) {
            return const UiEmptyState(
              title: 'No courses yet',
              message: 'Add a course to start logging assessments and tracking your grade.',
              icon: Icons.school_outlined,
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final course in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CourseCard(
                    course: course,
                    onTap: () => context.push('/courses/${course.id}'),
                    onDelete: () => _confirmDelete(context, ref, course),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CourseCard extends ConsumerWidget {
  const _CourseCard({
    required this.course,
    required this.onTap,
    required this.onDelete,
  });

  final Course course;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.uiColors;
    final assessmentsAsync = ref.watch(
      courseAssessmentsStreamProvider(course.id),
    );
    final assessments = assessmentsAsync.value ?? const <Assessment>[];
    final average = weightedAverage(assessments);
    final hasTarget = course.targetGrade != null;
    final meetsTarget = !hasTarget || average >= course.targetGrade!;
    final intent = assessments.isEmpty
        ? UiIntent.neutral
        : (meetsTarget ? UiIntent.success : UiIntent.danger);

    return UiCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(course.name, style: context.uiText.bodyStrong),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    UiBadge(
                      label: '${assessments.length} assessment${assessments.length == 1 ? '' : 's'}',
                      intent: UiIntent.neutral,
                      size: UiSize.sm,
                    ),
                    if (hasTarget)
                      UiBadge(
                        label: 'Target ${_trimNum(course.targetGrade!)}',
                        intent: UiIntent.info,
                        size: UiSize.sm,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                assessments.isEmpty ? '—' : '${average.toStringAsFixed(1)}%',
                style: context.uiText.heading.copyWith(
                  color: assessments.isEmpty ? c.foregroundMuted : intent.color(context),
                ),
              ),
              const SizedBox(height: 6),
              UiIconButton(
                icon: Icons.delete_outline,
                variant: UiVariant.ghost,
                size: UiSize.sm,
                tooltip: 'Delete course',
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _trimNum(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _CoursesSkeleton extends StatelessWidget {
  const _CoursesSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(
        3,
        (_) => const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: UiCard(loading: true, loadingHeight: 90, child: SizedBox.shrink()),
        ),
      ),
    );
  }
}
