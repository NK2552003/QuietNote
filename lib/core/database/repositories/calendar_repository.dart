import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;
import 'package:quietnote/core/database/repositories/task_repository.dart';
import 'package:quietnote/core/database/repositories/goal_repository.dart';
import 'package:quietnote/core/database/repositories/habit_repository.dart';

final calendarRepositoryProvider = Provider<CalendarRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CalendarRepository(db);
});

final calendarEventsStreamProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final repo = ref.watch(calendarRepositoryProvider);
  return repo.watchAllEvents();
});

/// Aggregated calendar events: database events plus scheduled items from
/// tasks, goals and habits so the calendar shows anything that has a date.
final aggregatedCalendarEventsProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final controller = StreamController<List<CalendarEvent>>();

  List<CalendarEvent> dbEvents = <CalendarEvent>[];
  List<Task> tasks = <Task>[];
  List<Goal> goals = <Goal>[];
  List<Habit> habits = <Habit>[];

  void emit() {
    final List<CalendarEvent> combined = <CalendarEvent>[];
    combined.addAll(dbEvents);

    for (final t in tasks) {
      if (t.dueDate != null) {
        combined.add(CalendarEvent(
          id: 'task:${t.id}',
          title: 'Task: ${t.title}',
          description: t.subtitle.isEmpty ? null : t.subtitle,
          startTime: t.dueDate!,
          endTime: t.dueDate!.add(const Duration(hours: 1)),
          isAllDay: false,
          color: null,
          category: 'Task',
          recurrenceRule: null,
          reminderOffset: t.reminderOffset,
          linkedGoalId: t.linkedGoalId,
        ));
      }
    }

    for (final g in goals) {
      if (g.deadline != null) {
        final isAllDay = g.deadline!.hour == 0 && g.deadline!.minute == 0;
        combined.add(CalendarEvent(
          id: 'goal:${g.id}',
          title: 'Goal: ${g.title}',
          description: null,
          startTime: g.deadline!,
          endTime: g.deadline!.add(const Duration(hours: 1)),
          isAllDay: isAllDay,
          color: null,
          category: 'Goal',
          recurrenceRule: null,
          reminderOffset: null,
          linkedGoalId: g.id,
        ));
      }
    }

    for (final h in habits) {
      if (h.reminderTime != null) {
        // Treat habit reminderTime as a scheduled one-off if it has a date.
        final dt = h.reminderTime!;
        combined.add(CalendarEvent(
          id: 'habit:${h.id}:${dt.toIso8601String()}',
          title: 'Habit: ${h.title}',
          description: h.subtitle.isEmpty ? null : h.subtitle,
          startTime: dt,
          endTime: dt.add(const Duration(minutes: 30)),
          isAllDay: false,
          color: null,
          category: 'Habit',
          recurrenceRule: null,
          reminderOffset: null,
          linkedGoalId: null,
        ));
      }
    }

    controller.add(combined);
  }

  final subs = <StreamSubscription>[];
  subs.add(ref.watch(calendarEventsStreamProvider.stream).listen((e) {
    dbEvents = e;
    emit();
  }));
  subs.add(ref.watch(tasksStreamProvider.stream).listen((e) {
    tasks = e;
    emit();
  }));
  subs.add(ref.watch(goalsStreamProvider.stream).listen((e) {
    goals = e;
    emit();
  }));
  subs.add(ref.watch(habitsStreamProvider.stream).listen((e) {
    habits = e;
    emit();
  }));

  ref.onDispose(() async {
    for (final s in subs) {
      await s.cancel();
    }
    await controller.close();
  });

  return controller.stream;
});

class CalendarRepository {
  final AppDatabase _db;
  CalendarRepository(this._db);

  Stream<List<CalendarEvent>> watchAllEvents() {
    return _db.select(_db.calendarEvents).watch();
  }

  Future<CalendarEvent?> getEventById(String id) {
    return (_db.select(_db.calendarEvents)..where((e) => e.id.equals(id))).getSingleOrNull();
  }

  Future<String> addEvent(
    String title,
    DateTime startTime,
    DateTime endTime, {
    String? description,
    bool isAllDay = false,
    int? color,
    String? category,
    String? recurrenceRule,
    int? reminderOffset,
    String? linkedGoalId,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.calendarEvents).insert(CalendarEventsCompanion.insert(
          id: id,
          title: title,
          startTime: startTime,
          endTime: endTime,
          description: drift.Value(description),
          isAllDay: drift.Value(isAllDay),
          color: drift.Value(color),
          category: drift.Value(category),
          recurrenceRule: drift.Value(recurrenceRule),
          reminderOffset: drift.Value(reminderOffset),
          linkedGoalId: drift.Value(linkedGoalId),
        ));
    return id;
  }

  Future<void> updateEvent(
    String id, {
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
    bool isAllDay = false,
    int? color,
    String? category,
    String? recurrenceRule,
    int? reminderOffset,
    String? linkedGoalId,
  }) async {
    await (_db.update(_db.calendarEvents)..where((e) => e.id.equals(id))).write(
      CalendarEventsCompanion(
        title: drift.Value(title),
        startTime: drift.Value(startTime),
        endTime: drift.Value(endTime),
        description: drift.Value(description),
        isAllDay: drift.Value(isAllDay),
        color: drift.Value(color),
        category: drift.Value(category),
        recurrenceRule: drift.Value(recurrenceRule),
        reminderOffset: drift.Value(reminderOffset),
        linkedGoalId: drift.Value(linkedGoalId),
      ),
    );
  }

  Future<void> deleteEvent(String id) async {
    await (_db.delete(_db.calendarEvents)..where((e) => e.id.equals(id))).go();
  }
}
