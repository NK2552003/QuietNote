import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'dart:io';

part 'database.g.dart';

class Habits extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().withDefault(const Constant(''))();
  IntColumn get streak => integer().withDefault(const Constant(0))();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  DateTimeColumn get startDate => dateTime().nullable()();
  IntColumn get durationDays => integer().nullable()();

  // Phase 2.5 new fields
  TextColumn get frequencyType => text().withDefault(const Constant('daily'))();
  TextColumn get daysOfWeek => text().nullable()(); // CSV of ints 0-6
  IntColumn get intervalDays => integer().nullable()();
  IntColumn get targetPerPeriod => integer().nullable()();
  DateTimeColumn get reminderTime => dateTime().nullable()();

  // Phase 3 new fields
  TextColumn get category => text().nullable()();
  IntColumn get priority =>
      integer().withDefault(const Constant(0))(); // 0=None,1=Low,2=Med,3=High
  TextColumn get notes => text().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  RealColumn get goalTarget =>
      real().nullable()(); // e.g. 3 (miles), 8 (glasses)
  TextColumn get goalUnit =>
      text().nullable()(); // e.g. "miles", "glasses", "pages"
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per day a habit was acted on — powers the weekly strip, the
/// month calendar heatmap and the statistics charts. A habit with no
/// `HabitEntries` rows for a given day is simply "not logged" for that day.
@DataClassName('HabitEntry')
class HabitEntries extends Table {
  TextColumn get id => text()();
  TextColumn get habitId => text()();
  DateTimeColumn get date =>
      dateTime()(); // stored truncated to midnight (local day)
  BoolColumn get isDone => boolean().withDefault(const Constant(true))();
  RealColumn get value =>
      real().nullable()(); // logged amount for quantified goals
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Tasks extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().withDefault(const Constant(''))();
  TextColumn get details => text().nullable()();
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(
    const Constant(0),
  )(); // 0=None, 1=Low, 2=Med, 3=High

  // Phase 2.5 new fields
  TextColumn get subtasks => text().nullable()(); // JSON string
  TextColumn get recurrenceRule => text().nullable()();
  TextColumn get linkedGoalId => text().nullable()();
  IntColumn get reminderOffset => integer().nullable()(); // minutes
  TextColumn get courseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Notes extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get content => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Comma-separated subject/topic tags (e.g. "Biology,Exam prep"), same CSV
  /// convention already used by `imagePaths` and `daysOfWeek` elsewhere in
  /// this schema.
  TextColumn get tags => text().nullable()();
  TextColumn get courseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Journal extends Table {
  TextColumn get id => text()();

  /// A separate title makes entries scannable without treating the first
  /// sentence of the private entry as an accidental heading.
  TextColumn get title =>
      text().withDefault(const Constant('Untitled entry'))();
  TextColumn get entry => text()();
  TextColumn get mood => text().nullable()();
  TextColumn get imagePaths => text().nullable()(); // Comma separated paths

  /// Comma-separated subject/topic tags, same CSV convention as [imagePaths].
  TextColumn get tags => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  RealColumn get target => real()();
  RealColumn get current => real().withDefault(const Constant(0.0))();
  DateTimeColumn get deadline => dateTime().nullable()();

  // Phase 2.5 new fields
  TextColumn get category => text().nullable()();
  IntColumn get progressPercent => integer().withDefault(const Constant(0))();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get milestones => text().nullable()(); // JSON string
  TextColumn get courseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Routines extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get timeOfDay => text()(); // e.g. "Morning", "Evening"
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

class CalendarEvents extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  BoolColumn get isAllDay => boolean().withDefault(const Constant(false))();
  IntColumn get color => integer().nullable()(); // ARGB integer

  // Phase 2.5 new fields
  TextColumn get category => text().nullable()();
  TextColumn get recurrenceRule => text().nullable()();
  IntColumn get reminderOffset => integer().nullable()();
  TextColumn get linkedGoalId => text().nullable()();
  TextColumn get courseId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get parentId => text()(); // Note, Journal, Todo, Event, Goal ID
  TextColumn get parentType => text()(); // 'note', 'journal', etc.
  TextColumn get filePath => text()();
  TextColumn get caption => text().nullable()();
  IntColumn get positionInBody => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A durable record of a focus timer. Keeping this separate from preferences
/// makes completed sessions available for history and prevents an app restart
/// from losing an in-progress timer.
class FocusSessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();
  IntColumn get durationMinutes => integer()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// Number of completed work→break→work loops for a Pomodoro-style preset
  /// session (see Feature 3, study-session presets).
  IntColumn get cyclesCompleted =>
      integer().withDefault(const Constant(0))();

  /// The [FocusPreset] name this session was started from, or `null` for a
  /// manually-entered custom duration.
  TextColumn get presetId => text().nullable()();

  TextColumn get courseId => text().nullable()();
  TextColumn get taskId => text().nullable()();
  TextColumn get habitId => text().nullable()();
  TextColumn get reflection => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// A course/class the student is tracking grades for (Feature 5, grade
/// tracker). `targetGrade` is stored on whatever scale the student enters it
/// on (percentage or GPA) — we never rescale it, just compare like-for-like
/// against the weighted average computed from that course's [Assessments].
class Courses extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  RealColumn get targetGrade => real().nullable()();
  TextColumn get code => text().nullable()(); // e.g. CS101
  TextColumn get instructor => text().nullable()();
  TextColumn get room => text().nullable()();
  IntColumn get color => integer().nullable()();
  TextColumn get schedule => text().nullable()();
  TextColumn get term => text().nullable()();
  TextColumn get notes => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

/// A single graded item (quiz, exam, assignment) within a [Courses] row.
/// `weight` defaults to 1.0 so ungraded/unweighted assessments still average
/// sensibly alongside weighted ones.
class Assessments extends Table {
  TextColumn get id => text()();
  TextColumn get courseId => text()();
  TextColumn get name => text()();
  RealColumn get score => real()();
  RealColumn get maxScore => real()();
  RealColumn get weight => real().withDefault(const Constant(1.0))();
  DateTimeColumn get date => dateTime().withDefault(currentDateAndTime)();
  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Habits,
    Tasks,
    Notes,
    Journal,
    Goals,
    Routines,
    CalendarEvents,
    Attachments,
    HabitEntries,
    FocusSessions,
    Courses,
    Assessments,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 11; // v11: rich courses & focus session linking

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // IMPORTANT: `m.createTable(x)` always builds the table using the
        // CURRENT Dart schema definition (i.e. every column that exists
        // today), not just the columns that existed "as of" some old
        // version. So a table created here already has every column below.
        // We must never `addColumn` a column that was part of the table's
        // definition at the moment it was created via `createTable`, or
        // Drift throws a "duplicate column" SqliteException and the
        // connection future can hang/fail silently — which is exactly what
        // was causing every non-Home tab to sit on an infinite loading
        // spinner with nothing printed to the console.
        if (from == 1) {
          // v1 -> v2: add columns that existed on ALREADY-created tables.
          await m.addColumn(habits, habits.startDate);
          await m.addColumn(habits, habits.durationDays);
          await m.addColumn(tasks, tasks.details);
          await m.addColumn(tasks, tasks.priority);
          await m.addColumn(journal, journal.imagePaths);
          await m.addColumn(goals, goals.deadline);

          // Brand-new tables: created with the FULL current schema, so no
          // matching addColumn calls should ever run against them here.
          await m.createTable(routines);
          await m.createTable(calendarEvents);
        }

        if (from >= 2 && from < 3) {
          // v2 -> v3: routines/calendarEvents already existed (created at
          // v1->v2 with the full current schema), so only add the new
          // "Phase 2.5" columns to tables that predate calendarEvents/
          // routines's Phase 2.5 fields, i.e. everything except those two.
          await m.addColumn(habits, habits.frequencyType);
          await m.addColumn(habits, habits.daysOfWeek);
          await m.addColumn(habits, habits.intervalDays);
          await m.addColumn(habits, habits.targetPerPeriod);
          await m.addColumn(habits, habits.reminderTime);

          await m.addColumn(tasks, tasks.subtasks);
          await m.addColumn(tasks, tasks.recurrenceRule);
          await m.addColumn(tasks, tasks.linkedGoalId);
          await m.addColumn(tasks, tasks.reminderOffset);

          await m.addColumn(goals, goals.category);
          await m.addColumn(goals, goals.progressPercent);
          await m.addColumn(goals, goals.priority);
          await m.addColumn(goals, goals.milestones);

          await m.createTable(attachments);
        } else if (from == 1) {
          // from == 1 skips the `from >= 2` branch above, but routines and
          // calendarEvents were just created fresh (full schema) two lines
          // up, so ONLY the attachments table (which didn't exist at all
          // yet) needs creating — no addColumn calls needed for anything.
          await m.createTable(attachments);
        }

        if (from >= 1 && from < 4) {
          // -> v4: add the "Phase 3" habit-tracking columns to the ONE
          // table that predates them (habits). habitEntries is brand new,
          // so it only ever needs createTable — never addColumn.
          await m.addColumn(habits, habits.category);
          await m.addColumn(habits, habits.priority);
          await m.addColumn(habits, habits.notes);
          await m.addColumn(habits, habits.endDate);
          await m.addColumn(habits, habits.goalTarget);
          await m.addColumn(habits, habits.goalUnit);
          await m.addColumn(habits, habits.archived);

          await m.createTable(habitEntries);
        }

        if (from >= 4 && from < 5) {
          // -> v5: some databases were already at schema version 4 but the
          // `habitEntries` table was never physically created — the previous
          // build's stale generated code couldn't compile the migration that
          // created it, so it silently never ran. Any query against
          // `habit_entries` then failed, which is what made every non-Home
          // tab render blank. `createTable` uses `CREATE TABLE IF NOT EXISTS`,
          // so this is safe whether the table exists or not.
          await m.createTable(habitEntries);
        }

        if (from < 6) {
          await m.addColumn(journal, journal.title);
        }
        if (from < 7) {
          await m.createTable(focusSessions);
        }
        if (from < 8) {
          await m.addColumn(notes, notes.tags);
          await m.addColumn(journal, journal.tags);
        }
        if (from < 9) {
          await m.addColumn(focusSessions, focusSessions.cyclesCompleted);
          await m.addColumn(focusSessions, focusSessions.presetId);
        }
        if (from < 10) {
          // Courses/Assessments are brand-new tables, so — same as
          // routines/attachments/habitEntries/focusSessions before them —
          // this is just createTable, never addColumn.
          await m.createTable(courses);
          await m.createTable(assessments);
        }
        if (from < 11) {
          await m.addColumn(courses, courses.code);
          await m.addColumn(courses, courses.instructor);
          await m.addColumn(courses, courses.room);
          await m.addColumn(courses, courses.color);
          await m.addColumn(courses, courses.schedule);
          await m.addColumn(courses, courses.term);
          await m.addColumn(courses, courses.notes);

          await m.addColumn(focusSessions, focusSessions.courseId);
          await m.addColumn(focusSessions, focusSessions.taskId);
          await m.addColumn(focusSessions, focusSessions.habitId);
          await m.addColumn(focusSessions, focusSessions.reflection);

          await m.addColumn(tasks, tasks.courseId);
          await m.addColumn(notes, notes.courseId);
          await m.addColumn(calendarEvents, calendarEvents.courseId);
          await m.addColumn(goals, goals.courseId);
        }
      },
      beforeOpen: (details) async {
        // Defense in depth: if a future migration mistake still slips
        // through, fail loudly with a clear message instead of a silent
        // hang, so the UI can surface something actionable instead of a
        // blank screen.
        await customStatement('PRAGMA foreign_keys = ON');
      },
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    try {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'db.sqlite'));
      return NativeDatabase.createInBackground(file, logStatements: false);
    } catch (e, st) {
      // Surface connection/init failures instead of letting them vanish
      // inside the background isolate, which is what previously caused
      // every screen but Home (the only screen that doesn't touch the DB)
      // to hang forever on a loading spinner with no console output.
      // ignore: avoid_print
      print('QuietNote: failed to open database: $e\n$st');
      rethrow;
    }
  });
}
