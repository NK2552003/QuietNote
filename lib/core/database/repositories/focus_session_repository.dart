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

final allFocusSessionsProvider = StreamProvider<List<FocusSession>>((ref) {
  return ref.watch(focusSessionRepositoryProvider).watchAll();
});

/// Computes the comprehensive total focus minutes across sessions, accounting for
/// completed Pomodoro cycles, elapsed minutes in interrupted/cancelled sessions,
/// and currently active live sessions.
int computeTotalFocusMinutes(
  List<FocusSession> sessions, {
  FocusSession? activeSession,
  DateTime? forDay,
}) {
  int total = 0;
  final now = DateTime.now();

  for (final s in sessions) {
    if (forDay != null) {
      final sDay = DateTime(s.startedAt.year, s.startedAt.month, s.startedAt.day);
      final targetDay = DateTime(forDay.year, forDay.month, forDay.day);
      if (sDay != targetDay) continue;
    }

    if (s.status == 'completed') {
      final multiplier = (s.cyclesCompleted > 0) ? (s.cyclesCompleted + 1) : 1;
      total += (s.durationMinutes * multiplier);
    } else if (s.status == 'cancelled' && s.endedAt != null) {
      final elapsed = s.endedAt!.difference(s.startedAt).inMinutes;
      final cycleBonus = s.cyclesCompleted * s.durationMinutes;
      total += (elapsed > 0 ? elapsed : 0) + cycleBonus;
    } else if (s.status == 'active') {
      final elapsed = (s.endedAt ?? now).difference(s.startedAt).inMinutes;
      final cycleBonus = s.cyclesCompleted * s.durationMinutes;
      total += (elapsed > 0 ? elapsed : 0) + cycleBonus;
    }
  }

  if (activeSession != null && !sessions.any((s) => s.id == activeSession.id)) {
    final aDay = DateTime(activeSession.startedAt.year, activeSession.startedAt.month, activeSession.startedAt.day);
    if (forDay == null || aDay == DateTime(forDay.year, forDay.month, forDay.day)) {
      final elapsed = now.difference(activeSession.startedAt).inMinutes;
      final cycleBonus = activeSession.cyclesCompleted * activeSession.durationMinutes;
      total += (elapsed > 0 ? elapsed : 0) + cycleBonus;
    }
  }

  return total;
}

/// The single in-progress session (work or break phase), if any. Chaining a
/// work interval into a break (and back) keeps reusing this same row — see
/// [FocusSessionRepository.extendActive].
final activeFocusSessionProvider = StreamProvider<FocusSession?>((ref) {
  return ref.watch(focusSessionRepositoryProvider).watchActive();
});

class FocusSessionRepository {
  FocusSessionRepository(this._db);
  final AppDatabase _db;

  Stream<List<FocusSession>> watchRecent() =>
      (_db.select(_db.focusSessions)..orderBy([(t) => drift.OrderingTerm.desc(t.startedAt)])..limit(20)).watch();

  Stream<List<FocusSession>> watchAll() =>
      (_db.select(_db.focusSessions)..orderBy([(t) => drift.OrderingTerm.desc(t.startedAt)])).watch();

  Stream<FocusSession?> watchActive() =>
      (_db.select(_db.focusSessions)..where((t) => t.status.equals('active')))
          .watchSingleOrNull();

  Future<String> start({
    required DateTime endsAt,
    required int minutes,
    String? presetId,
    String? courseId,
    String? taskId,
    String? habitId,
    String? reflection,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now();
    await _db.transaction(() async {
      await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
        FocusSessionsCompanion(status: const drift.Value('cancelled'), endedAt: drift.Value(now)),
      );
      await _db.into(_db.focusSessions).insert(FocusSessionsCompanion.insert(
        id: id,
        startedAt: now,
        endsAt: endsAt,
        durationMinutes: minutes,
        presetId: drift.Value(presetId),
        courseId: drift.Value(courseId),
        taskId: drift.Value(taskId),
        habitId: drift.Value(habitId),
        reflection: drift.Value(reflection),
      ));
    });
    return id;
  }

  /// Reuses the active session row for the next phase of a chained
  /// Pomodoro-style timer (work -> break, or break -> next work), instead of
  /// finishing the row and starting a new one, so the whole chain stays one
  /// history entry.
  Future<void> extendActive({required DateTime endsAt}) async {
    await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
      FocusSessionsCompanion(endsAt: drift.Value(endsAt)),
    );
  }

  /// Marks one full work -> break -> work loop complete on the active
  /// session. Called when a break interval ends and the student is offered
  /// the next work interval.
  Future<void> incrementCycle() async {
    final active = await (_db.select(_db.focusSessions)..where((t) => t.status.equals('active'))).getSingleOrNull();
    if (active == null) return;
    await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
      FocusSessionsCompanion(cyclesCompleted: drift.Value(active.cyclesCompleted + 1)),
    );
  }

  Future<void> finishActive({bool? cancelled, String? reflection}) async {
    final active = await (_db.select(_db.focusSessions)..where((t) => t.status.equals('active'))).getSingleOrNull();
    // A session is 'cancelled' only when:
    //   • The user explicitly ended it early (cancelled == true), AND
    //   • The timer still has meaningful time left (>2 s), AND
    //   • No full Pomodoro cycle has been completed yet (cyclesCompleted == 0).
    // If the user completed at least one work→break→work cycle, we honour
    // that as 'completed' regardless of whether there's time remaining.
    final bool isActuallyCancelled = (cancelled == true) &&
        (active != null &&
            active.cyclesCompleted == 0 &&
            active.endsAt.isAfter(DateTime.now().add(const Duration(seconds: 2))));
    await (_db.update(_db.focusSessions)..where((t) => t.status.equals('active'))).write(
      FocusSessionsCompanion(
        status: drift.Value(isActuallyCancelled ? 'cancelled' : 'completed'),
        endedAt: drift.Value(DateTime.now()),
        reflection: reflection != null ? drift.Value(reflection) : const drift.Value.absent(),
      ),
    );
  }

  Future<void> saveReflection(String id, String reflection) async {
    await (_db.update(_db.focusSessions)..where((t) => t.id.equals(id))).write(
      FocusSessionsCompanion(reflection: drift.Value(reflection)),
    );
  }
}
