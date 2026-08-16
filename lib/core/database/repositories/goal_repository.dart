import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final goalRepositoryProvider = Provider<GoalRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return GoalRepository(db);
});

final goalsStreamProvider = StreamProvider<List<Goal>>((ref) {
  final repo = ref.watch(goalRepositoryProvider);
  return repo.watchAllGoals();
});

class GoalRepository {
  final AppDatabase _db;
  GoalRepository(this._db);

  Stream<List<Goal>> watchAllGoals() {
    return _db.select(_db.goals).watch();
  }

  Future<Goal?> getGoalById(String id) {
    return (_db.select(_db.goals)..where((g) => g.id.equals(id))).getSingleOrNull();
  }

  Future<String> addGoal(
    String title,
    double target, {
    double current = 0,
    DateTime? deadline,
    String? category,
    int priority = 0,
    String? milestones,
    String? courseId,
  }) async {
    final id = const Uuid().v4();
    final percent = target == 0 ? 0 : ((current / target) * 100).clamp(0, 100).toInt();
    await _db.into(_db.goals).insert(GoalsCompanion.insert(
          id: id,
          title: title,
          target: target,
          current: drift.Value(current),
          deadline: drift.Value(deadline),
          category: drift.Value(category),
          progressPercent: drift.Value(percent),
          priority: drift.Value(priority),
          milestones: drift.Value(milestones),
          courseId: drift.Value(courseId),
        ));
    return id;
  }

  /// Full edit of a goal's structure (title, target, deadline, category,
  /// priority, milestones). Recomputes progress% from current/target so the
  /// ring on the list screen stays accurate even if the target changed.
  Future<void> updateGoal(
    String id, {
    required String title,
    required double target,
    required double current,
    DateTime? deadline,
    String? category,
    int priority = 0,
    String? milestones,
    String? courseId,
  }) async {
    final percent = target == 0 ? 0 : ((current / target) * 100).clamp(0, 100).toInt();
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(
        title: drift.Value(title),
        target: drift.Value(target),
        current: drift.Value(current),
        deadline: drift.Value(deadline),
        category: drift.Value(category),
        progressPercent: drift.Value(percent),
        priority: drift.Value(priority),
        milestones: drift.Value(milestones),
        courseId: drift.Value(courseId),
      ),
    );
  }

  /// Quick progress-only update used by the +1 / milestone-toggle actions on
  /// the goals list, without touching the goal's other fields.
  Future<void> updateGoalProgress(String id, double current, int progressPercent, String? milestones) async {
    await (_db.update(_db.goals)..where((g) => g.id.equals(id))).write(
      GoalsCompanion(
        current: drift.Value(current),
        progressPercent: drift.Value(progressPercent),
        milestones: drift.Value(milestones),
      ),
    );
  }

  Future<void> deleteGoal(String id) async {
    await (_db.delete(_db.goals)..where((g) => g.id.equals(id))).go();
  }
}
