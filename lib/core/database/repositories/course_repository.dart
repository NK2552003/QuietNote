import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CourseRepository(db);
});

final coursesStreamProvider = StreamProvider<List<Course>>((ref) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchAllCourses();
});

/// All assessments for a single course, newest first. Keyed by course id so
/// the course detail screen (and the analytics academics section) can watch
/// just the rows it needs.
final courseAssessmentsStreamProvider =
    StreamProvider.family<List<Assessment>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchAssessmentsForCourse(courseId);
});

/// Every assessment across every course, used by the analytics "Academics"
/// section to compute a mean weighted average without a stream-per-course.
final allAssessmentsStreamProvider = StreamProvider<List<Assessment>>((ref) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchAllAssessments();
});

final courseTasksStreamProvider =
    StreamProvider.family<List<Task>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchTasksForCourse(courseId);
});

final courseNotesStreamProvider =
    StreamProvider.family<List<Note>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchNotesForCourse(courseId);
});

final courseEventsStreamProvider =
    StreamProvider.family<List<CalendarEvent>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchEventsForCourse(courseId);
});

final courseFocusSessionsStreamProvider =
    StreamProvider.family<List<FocusSession>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchFocusSessionsForCourse(courseId);
});

final courseGoalsStreamProvider =
    StreamProvider.family<List<Goal>, String>((ref, courseId) {
  final repo = ref.watch(courseRepositoryProvider);
  return repo.watchGoalsForCourse(courseId);
});

/// Weighted average (0-100 scale) across a set of assessments, following the
/// grade-tracker spec: each assessment contributes `score/maxScore*100`
/// scaled by its `weight`. Returns 0 for an empty list or when every weight
/// is 0, so callers never divide by zero.
double weightedAverage(List<Assessment> items) {
  if (items.isEmpty) return 0;
  final totalWeight = items.fold(0.0, (sum, a) => sum + a.weight);
  if (totalWeight == 0) return 0;
  final weightedSum = items.fold(
    0.0,
    (sum, a) => sum + (a.score / a.maxScore * 100) * a.weight,
  );
  return weightedSum / totalWeight;
}

class CourseRepository {
  final AppDatabase _db;
  CourseRepository(this._db);

  Stream<List<Course>> watchAllCourses() {
    return (_db.select(_db.courses)
          ..orderBy([(c) => drift.OrderingTerm.asc(c.name)]))
        .watch();
  }

  Future<Course?> getCourseById(String id) {
    return (_db.select(_db.courses)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
  }

  Stream<List<Assessment>> watchAssessmentsForCourse(String courseId) {
    return (_db.select(_db.assessments)
          ..where((a) => a.courseId.equals(courseId))
          ..orderBy([(a) => drift.OrderingTerm.desc(a.date)]))
        .watch();
  }

  Stream<List<Assessment>> watchAllAssessments() {
    return _db.select(_db.assessments).watch();
  }

  Stream<List<Task>> watchTasksForCourse(String courseId) {
    return (_db.select(_db.tasks)
          ..where((t) => t.courseId.equals(courseId))
          ..orderBy([(t) => drift.OrderingTerm.desc(t.dueDate)]))
        .watch();
  }

  Stream<List<Note>> watchNotesForCourse(String courseId) {
    return (_db.select(_db.notes)
          ..where((n) => n.courseId.equals(courseId))
          ..orderBy([(n) => drift.OrderingTerm.desc(n.createdAt)]))
        .watch();
  }

  Stream<List<CalendarEvent>> watchEventsForCourse(String courseId) {
    return (_db.select(_db.calendarEvents)
          ..where((e) => e.courseId.equals(courseId))
          ..orderBy([(e) => drift.OrderingTerm.asc(e.startTime)]))
        .watch();
  }

  Stream<List<FocusSession>> watchFocusSessionsForCourse(String courseId) {
    return (_db.select(_db.focusSessions)
          ..where((s) => s.courseId.equals(courseId))
          ..orderBy([(s) => drift.OrderingTerm.desc(s.startedAt)]))
        .watch();
  }

  Stream<List<Goal>> watchGoalsForCourse(String courseId) {
    return (_db.select(_db.goals)..where((g) => g.courseId.equals(courseId)))
        .watch();
  }

  Future<String> addCourse(
    String name, {
    double? targetGrade,
    String? code,
    String? instructor,
    String? room,
    int? color,
    String? schedule,
    String? term,
    String? notes,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.courses).insert(
          CoursesCompanion.insert(
            id: id,
            name: name,
            targetGrade: drift.Value(targetGrade),
            code: drift.Value(code),
            instructor: drift.Value(instructor),
            room: drift.Value(room),
            color: drift.Value(color),
            schedule: drift.Value(schedule),
            term: drift.Value(term),
            notes: drift.Value(notes),
          ),
        );
    return id;
  }

  Future<void> updateCourse(
    String id, {
    required String name,
    double? targetGrade,
    String? code,
    String? instructor,
    String? room,
    int? color,
    String? schedule,
    String? term,
    String? notes,
  }) async {
    await (_db.update(_db.courses)..where((c) => c.id.equals(id))).write(
      CoursesCompanion(
        name: drift.Value(name),
        targetGrade: drift.Value(targetGrade),
        code: drift.Value(code),
        instructor: drift.Value(instructor),
        room: drift.Value(room),
        color: drift.Value(color),
        schedule: drift.Value(schedule),
        term: drift.Value(term),
        notes: drift.Value(notes),
      ),
    );
  }

  /// Deletes a course and every assessment that belongs to it.
  Future<void> deleteCourse(String id) async {
    await _db.transaction(() async {
      await (_db.delete(_db.assessments)..where((a) => a.courseId.equals(id)))
          .go();
      await (_db.delete(_db.courses)..where((c) => c.id.equals(id))).go();
    });
  }

  Future<String> addAssessment(
    String courseId,
    String name, {
    required double score,
    required double maxScore,
    double weight = 1.0,
    DateTime? date,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.assessments).insert(
          AssessmentsCompanion.insert(
            id: id,
            courseId: courseId,
            name: name,
            score: score,
            maxScore: maxScore,
            weight: drift.Value(weight),
            date: date == null ? const drift.Value.absent() : drift.Value(date),
          ),
        );
    return id;
  }

  Future<void> updateAssessment(
    String id, {
    required String name,
    required double score,
    required double maxScore,
    required double weight,
    required DateTime date,
  }) async {
    await (_db.update(_db.assessments)..where((a) => a.id.equals(id))).write(
      AssessmentsCompanion(
        name: drift.Value(name),
        score: drift.Value(score),
        maxScore: drift.Value(maxScore),
        weight: drift.Value(weight),
        date: drift.Value(date),
      ),
    );
  }

  Future<void> deleteAssessment(String id) async {
    await (_db.delete(_db.assessments)..where((a) => a.id.equals(id))).go();
  }
}
