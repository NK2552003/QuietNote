import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';
import 'package:quietnote/core/database/repositories/flashcard_repository.dart';
import 'package:quietnote/core/database/repositories/course_repository.dart';

import 'capture_parser.dart';

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

enum CaptureSaveResultKind { saved, navigate }

/// What a successful save handed back so the caller can show a recap tile or
/// navigate to a screen (e.g. the Clock for focus sessions).
class CaptureSaveResult {
  const CaptureSaveResult({
    required this.type,
    required this.title,
    required this.id,
    this.kind = CaptureSaveResultKind.saved,
    this.navigationPath,
    this.navigationExtra,
  });

  final CaptureType type;
  final String title;
  final String id;

  /// [CaptureSaveResultKind.navigate] means the AI screen should push
  /// [navigationPath] instead of showing a success toast.
  final CaptureSaveResultKind kind;
  final String? navigationPath;
  final Map<String, dynamic>? navigationExtra;
}

// ---------------------------------------------------------------------------
// Main save function
// ---------------------------------------------------------------------------

/// Writes [draft] into whichever repository matches [draft.type].
/// Now handles all 10 types with complete field coverage.
Future<CaptureSaveResult> saveCaptureDraft(
  WidgetRef ref,
  CaptureDraft draft,
) async {
  final title = draft.title.trim().isEmpty
      ? 'Untitled capture'
      : draft.title.trim();
  final details = draft.details.trim();
  String id;

  switch (draft.type) {
    // ── To-do ──────────────────────────────────────────────────────────────
    case CaptureType.todo:
      // Build subtasks JSON if any subtask strings exist
      String? subtasksJson;
      if (draft.subtasks.isNotEmpty) {
        subtasksJson = jsonEncode(
          draft.subtasks
              .where((s) => s.trim().isNotEmpty)
              .map((s) => {'title': s.trim(), 'isCompleted': false})
              .toList(),
        );
      }

      id = await ref.read(taskRepositoryProvider).addTask(
            title,
            details: details.isEmpty ? null : details,
            priority: draft.priority,
            dueDate: draft.dueDate,
            subtasks: subtasksJson,
            courseId: draft.courseId,
          );

    // ── Note ────────────────────────────────────────────────────────────────
    case CaptureType.note:
      await ref.read(noteRepositoryProvider).addNote(
            title,
            details,
            tags: draft.tags,
            courseId: draft.courseId,
          );
      id = title;

    // ── Journal ─────────────────────────────────────────────────────────────
    case CaptureType.journal:
      await ref.read(journalRepositoryProvider).addEntry(
            details.isEmpty ? title : details,
            title: title,
            mood: draft.mood,
          );
      id = title;

    // ── Calendar Event ──────────────────────────────────────────────────────
    case CaptureType.event:
      final start =
          draft.startTime ?? DateTime.now().add(const Duration(hours: 1));
      final end = draft.endTime ?? start.add(const Duration(hours: 1));
      id = await ref.read(calendarRepositoryProvider).addEvent(
            title,
            start,
            end,
            description: details.isEmpty ? null : details,
            category: draft.category == 'Other' ? null : draft.category,
            courseId: draft.courseId,
          );

    // ── Habit ───────────────────────────────────────────────────────────────
    case CaptureType.habit:
      id = await ref.read(habitRepositoryProvider).addHabit(
            title,
            category: draft.category == 'Other' ? null : draft.category,
            priority: draft.priority,
            frequencyType: draft.frequencyType,
            goalTarget: draft.habitGoalTarget,
            goalUnit: draft.habitGoalUnit,
            notes: draft.habitNotes.isEmpty ? null : draft.habitNotes,
          );

    // ── Routine ─────────────────────────────────────────────────────────────
    case CaptureType.routine:
      // The category field holds the time-of-day choice from the Q&A
      final timeOfDay = <String>['Morning', 'Afternoon', 'Evening', 'Night']
              .contains(draft.category)
          ? draft.category
          : _inferTimeOfDay(title, details);
      id = await ref.read(routineRepositoryProvider).addRoutine(
            title,
            timeOfDay,
            description: details.isEmpty ? null : details,
          );

    // ── Goal ────────────────────────────────────────────────────────────────
    case CaptureType.goal:
      // Encode milestones as JSON if provided
      String? milestonesJson;
      if (draft.milestones.isNotEmpty) {
        milestonesJson = jsonEncode(
          draft.milestones
              .where((m) => m.trim().isNotEmpty)
              .map((m) => {'title': m.trim(), 'isCompleted': false})
              .toList(),
        );
      }
      id = await ref.read(goalRepositoryProvider).addGoal(
            title,
            draft.goalTarget <= 0 ? 100 : draft.goalTarget,
            category: draft.category == 'Other' ? null : draft.category,
            deadline: draft.dueDate,
            priority: draft.priority,
            milestones: milestonesJson,
            courseId: draft.courseId,
          );

    // ── Flashcard Deck ──────────────────────────────────────────────────────
    case CaptureType.flashcard:
      final repo = ref.read(flashcardRepositoryProvider);
      id = await repo.createDeck(
        title: title,
        description: details.isEmpty ? null : details,
        subject: draft.flashcardSubjects,
        courseId: draft.courseId,
      );
      // Bulk-insert all AI-generated card pairs in one transaction
      if (draft.flashcardPairs.isNotEmpty) {
        final pairs = draft.flashcardPairs
            .where((p) => p.front.trim().isNotEmpty && p.back.trim().isNotEmpty)
            .map((p) => (front: p.front.trim(), back: p.back.trim()))
            .toList();
        if (pairs.isNotEmpty) {
          await repo.bulkAddCards(deckId: id, pairs: pairs);
        }
      }

    // ── Course ──────────────────────────────────────────────────────────────
    case CaptureType.course:
      id = await ref.read(courseRepositoryProvider).addCourse(
            title,
            code: draft.courseCode.isEmpty ? null : draft.courseCode,
            instructor: draft.courseInstructor.isEmpty ? null : draft.courseInstructor,
            room: draft.courseRoom.isEmpty ? null : draft.courseRoom,
            term: draft.courseTerm.isEmpty ? null : draft.courseTerm,
            targetGrade: draft.courseTargetGrade,
            notes: draft.courseNotes.isEmpty ? null : draft.courseNotes,
          );

    // ── Focus Session ───────────────────────────────────────────────────────
    // Focus sessions are not saved here — the Clock screen owns that lifecycle.
    // We return a navigation result so the AI screen pushes /clock with
    // pre-filled values.
    case CaptureType.focusSession:
      id = 'focus_${DateTime.now().millisecondsSinceEpoch}';
      return CaptureSaveResult(
        type: draft.type,
        title: title,
        id: id,
        kind: CaptureSaveResultKind.navigate,
        navigationPath: '/clock',
        navigationExtra: {
          'presetId': draft.focusPresetId ?? 'pomodoro',
          'courseId': draft.focusLinkedCourseId,
          'taskId': draft.focusLinkedTaskId,
        },
      );
  }

  return CaptureSaveResult(type: draft.type, title: title, id: id);
}

// ---------------------------------------------------------------------------
// Helper: infer routine time-of-day from text when Q&A wasn't completed
// ---------------------------------------------------------------------------

String _inferTimeOfDay(String title, String details) {
  final lower = '$title $details'.toLowerCase();
  if (lower.contains('morning') || lower.contains('wake') || lower.contains('breakfast')) {
    return 'Morning';
  }
  if (lower.contains('afternoon') || lower.contains('lunch') || lower.contains('midday')) {
    return 'Afternoon';
  }
  if (lower.contains('night') || lower.contains('bed') || lower.contains('sleep')) {
    return 'Night';
  }
  return 'Evening';
}
