import 'package:drift/drift.dart' as drift;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';

final focusSessionRepositoryProvider = Provider<FocusSessionRepository>((ref) {
  return FocusSessionRepository(ref.watch(databaseProvider));
});

final recentFocusSessionsProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusSessionRepositoryProvider).watchRecent();
});

class FocusSessionRepository {
  FocusSessionRepository(this._db);
  final AppDatabase _db;

  Stream<List<FocusSession>> watchRecent() =>
      (_db.select(_db.focusSessions)..orderBy([(t) => drift.OrderingTerm.desc(t.startedAt)])..limit(20)).watch();

  Future<String> start({required DateTime endsAt, required int minutes}) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
        FocusSessionsCompanion(status: const drift.Value('cancelled'), endedAt: drift.Value(now)),
      );
      await _db.into(_db.focusSessions).insert(FocusSessionsCompanion.insert(
        id: id, startedAt: now, endsAt: endsAt, durationMinutes: minutes,
      ));
    });
    return id;
  }

  Future<void> finishActive({bool cancelled = false}) async {
    await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
      FocusSessionsCompanion(
        status: drift.Value(cancelled ? 'cancelled' : 'completed'),
        endedAt: drift.Value(DateTime.now()),
      ),
    );
  }
}
