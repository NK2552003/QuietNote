import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final routineRepositoryProvider = Provider<RoutineRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return RoutineRepository(db);
});

final routinesStreamProvider = StreamProvider<List<Routine>>((ref) {
  final repo = ref.watch(routineRepositoryProvider);
  return repo.watchAllRoutines();
});

class RoutineRepository {
  final AppDatabase _db;
  RoutineRepository(this._db);

  Stream<List<Routine>> watchAllRoutines() {
    return _db.select(_db.routines).watch();
  }

  Future<Routine?> getRoutineById(String id) {
    return (_db.select(_db.routines)..where((r) => r.id.equals(id))).getSingleOrNull();
  }

  Future<String> addRoutine(String title, String timeOfDay, {String? description}) async {
    final id = const Uuid().v4();
    await _db.into(_db.routines).insert(RoutinesCompanion.insert(
      id: id,
      title: title,
      timeOfDay: timeOfDay,
      description: drift.Value(description),
    ));
    return id;
  }

  /// Full edit of a routine's structure (title, time block, steps/notes
  /// encoded into [description]). Mirrors [updateGoal] in GoalRepository.
  Future<void> updateRoutine(
    String id, {
    required String title,
    required String timeOfDay,
    String? description,
  }) async {
    await (_db.update(_db.routines)..where((r) => r.id.equals(id))).write(
      RoutinesCompanion(
        title: drift.Value(title),
        timeOfDay: drift.Value(timeOfDay),
        description: drift.Value(description),
      ),
    );
  }

  /// Quick step-checklist toggle from the list screen, without touching the
  /// routine's other fields.
  Future<void> updateRoutineDescription(String id, String? description) async {
    await (_db.update(_db.routines)..where((r) => r.id.equals(id))).write(
      RoutinesCompanion(
        description: drift.Value(description),
      ),
    );
  }

  Future<void> toggleRoutineActive(String id, bool isActive) async {
    await (_db.update(_db.routines)..where((r) => r.id.equals(id))).write(
      RoutinesCompanion(
        isActive: drift.Value(isActive),
      ),
    );
  }

  Future<void> deleteRoutine(String id) async {
    await (_db.delete(_db.routines)..where((r) => r.id.equals(id))).go();
  }
}
