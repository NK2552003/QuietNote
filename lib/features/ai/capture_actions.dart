import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/note_repository.dart';
import 'package:quietnote/core/database/repositories/journal_repository.dart';
import 'package:quietnote/core/database/repositories/calendar_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/routine_repository.dart';

import 'capture_parser.dart';

/// What a successful save handed back, so the caller can show a "Recently
/// captured" entry without re-querying the database.
class CaptureSaveResult {
  const CaptureSaveResult({
    required this.type,
    required this.title,
    required this.id,
  });
  final CaptureType type;
  final String title;
  final String id;
}

/// Writes [draft] into whichever repository matches [draft.type]. Shared by
/// the composer's quick-save button and the full review sheet so the two
/// paths can never drift apart.
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
    case CaptureType.todo:
      id = await ref
          .read(taskRepositoryProvider)
          .addTask(
            title,
            details: details,
            priority: draft.priority,
            dueDate: draft.dueDate,
          );
      break;
    case CaptureType.note:
      await ref.read(noteRepositoryProvider).addNote(title, details);
      id = title;
      break;
    case CaptureType.journal:
      await ref
          .read(journalRepositoryProvider)
          .addEntry(details.isEmpty ? title : details, mood: draft.mood);
      id = title;
      break;
    case CaptureType.event:
      final start =
          draft.startTime ?? DateTime.now().add(const Duration(hours: 1));
      final end = draft.endTime ?? start.add(const Duration(hours: 1));
      id = await ref
          .read(calendarRepositoryProvider)
          .addEvent(title, start, end, description: details);
      break;
    case CaptureType.habit:
      id = await ref
          .read(habitRepositoryProvider)
          .addHabit(
            title,
            category: draft.category,
            frequencyType: draft.frequencyType,
            notes: details,
          );
      break;
    case CaptureType.routine:
      final lower = '$title $details'.toLowerCase();
      final timeOfDay = lower.contains('morning')
          ? 'Morning'
          : lower.contains('afternoon')
          ? 'Afternoon'
          : lower.contains('night') || lower.contains('bed')
          ? 'Night'
          : 'Evening';
      id = await ref
          .read(routineRepositoryProvider)
          .addRoutine(
            title,
            timeOfDay,
            description: details.isEmpty ? null : details,
          );
      break;
    case CaptureType.goal:
      id = await ref
          .read(goalRepositoryProvider)
          .addGoal(
            title,
            draft.goalTarget <= 0 ? 100 : draft.goalTarget,
            category: draft.category,
            deadline: draft.dueDate,
          );
      break;
  }

  return CaptureSaveResult(type: draft.type, title: title, id: id);
}
