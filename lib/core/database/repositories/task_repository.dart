import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TaskRepository(db);
});

final tasksStreamProvider = StreamProvider<List<Task>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAllTasks();
});

/// Computes the next due date for a recurring task once its current
/// occurrence is completed.
DateTime nextRecurrenceDate(DateTime due, String rule) {
  switch (rule) {
    case 'daily':
      return due.add(const Duration(days: 1));
    case 'weekly':
      return due.add(const Duration(days: 7));
    case 'monthly':
      final nextMonth = due.month == 12 ? 1 : due.month + 1;
      final nextYear = due.month == 12 ? due.year + 1 : due.year;
      // Clamp the day so e.g. Jan 31 -> Feb 28 instead of throwing.
      final daysInNextMonth = DateTime(nextYear, nextMonth + 1, 0).day;
      final day = due.day > daysInNextMonth ? daysInNextMonth : due.day;
      return DateTime(nextYear, nextMonth, day, due.hour, due.minute);
    default:
      return due;
  }
}

class TaskRepository {
  final AppDatabase _db;
  TaskRepository(this._db);

  Stream<List<Task>> watchAllTasks() {
    return _db.select(_db.tasks).watch();
  }

  Future<Task?> getTaskById(String id) async {
    return (_db.select(_db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<String> addTask(
    String title, {
    String subtitle = '',
    String? details,
    int priority = 0,
    String? subtasks,
    DateTime? dueDate,
    String? recurrenceRule,
    String? linkedGoalId,
    int? reminderOffset,
    String? courseId,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: id,
          title: title,
          subtitle: drift.Value(subtitle),
          details: drift.Value(details),
          priority: drift.Value(priority),
          subtasks: drift.Value(subtasks),
          dueDate: drift.Value(dueDate),
          recurrenceRule: drift.Value(recurrenceRule),
          linkedGoalId: drift.Value(linkedGoalId),
          reminderOffset: drift.Value(reminderOffset),
          courseId: drift.Value(courseId),
        ));
    return id;
  }

  Future<void> updateTask(
    String id, {
    required String title,
    String subtitle = '',
    String? details,
    int priority = 0,
    String? subtasks,
    DateTime? dueDate,
    String? recurrenceRule,
    String? linkedGoalId,
    int? reminderOffset,
    String? courseId,
  }) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        title: drift.Value(title),
        subtitle: drift.Value(subtitle),
        details: drift.Value(details),
        priority: drift.Value(priority),
        subtasks: drift.Value(subtasks),
        dueDate: drift.Value(dueDate),
        recurrenceRule: drift.Value(recurrenceRule),
        linkedGoalId: drift.Value(linkedGoalId),
        reminderOffset: drift.Value(reminderOffset),
        courseId: drift.Value(courseId),
      ),
    );
  }

  Future<void> toggleTaskCompletion(String id, bool currentStatus) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(isCompleted: drift.Value(!currentStatus)),
    );
  }

  /// Toggles completion like [toggleTaskCompletion], but when a task with a
  /// [Task.recurrenceRule] and [Task.dueDate] is marked done it also spawns
  /// the next occurrence (fresh id, due date shifted forward, subtasks
  /// reset to unchecked) so recurring tasks keep showing up.
  Future<void> toggleCompletionWithRecurrence(Task task) async {
    final markingDone = !task.isCompleted;
    await (_db.update(_db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(isCompleted: drift.Value(markingDone)),
    );

    final rule = task.recurrenceRule;
    if (!markingDone || rule == null || rule.isEmpty || task.dueDate == null) return;

    String? resetSubtasks = task.subtasks;
    if (task.subtasks != null) {
      try {
        final list = (jsonDecode(task.subtasks!) as List).map((e) {
          final m = Map<String, dynamic>.from(e as Map);
          m['isCompleted'] = false;
          return m;
        }).toList();
        resetSubtasks = jsonEncode(list);
      } catch (_) {
        resetSubtasks = task.subtasks;
      }
    }

    await _db.into(_db.tasks).insert(TasksCompanion.insert(
          id: const Uuid().v4(),
          title: task.title,
          subtitle: drift.Value(task.subtitle),
          details: drift.Value(task.details),
          priority: drift.Value(task.priority),
          subtasks: drift.Value(resetSubtasks),
          dueDate: drift.Value(nextRecurrenceDate(task.dueDate!, rule)),
          recurrenceRule: drift.Value(rule),
          linkedGoalId: drift.Value(task.linkedGoalId),
          reminderOffset: drift.Value(task.reminderOffset),
        ));
  }

  Future<void> updateTaskSubtasks(String id, String subtasks) async {
    await (_db.update(_db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(subtasks: drift.Value(subtasks)),
    );
  }

  Future<void> deleteTask(String id) async {
    await (_db.delete(_db.tasks)..where((t) => t.id.equals(id))).go();
  }
}
