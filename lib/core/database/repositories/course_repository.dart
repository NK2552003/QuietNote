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

  Future<String> addCourse(String name, {double? targetGrade}) async {
    final id = const Uuid().v4();
    await _db.into(_db.courses).insert(
          CoursesCompanion.insert(
            id: id,
            name: name,
            targetGrade: drift.Value(targetGrade),
          ),
        );
    return id;
  }

  Future<void> updateCourse(
    String id, {
    required String name,
    double? targetGrade,
  }) async {
    await (_db.update(_db.courses)..where((c) => c.id.equals(id))).write(
      CoursesCompanion(
        name: drift.Value(name),
        targetGrade: drift.Value(targetGrade),
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
