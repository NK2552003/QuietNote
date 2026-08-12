import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final habitRepositoryProvider = Provider<HabitRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return HabitRepository(db);
});

final habitsStreamProvider = StreamProvider<List<Habit>>((ref) {
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchAllHabits();
});

/// All logged entries for a single habit, newest first. Keyed by habit id
/// so every habit card / detail screen can watch just its own history.
final habitEntriesStreamProvider = StreamProvider.family<List<HabitEntry>, String>((ref, habitId) {
  final repo = ref.watch(habitRepositoryProvider);
  return repo.watchEntriesForHabit(habitId);
});

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

class HabitRepository {
  final AppDatabase _db;
  HabitRepository(this._db);

  Stream<List<Habit>> watchAllHabits() {
    return (_db.select(_db.habits)..orderBy([(h) => drift.OrderingTerm.asc(h.title)])).watch();
  }

  Future<Habit?> getHabitById(String id) {
    return (_db.select(_db.habits)..where((h) => h.id.equals(id))).getSingleOrNull();
  }

  Stream<List<HabitEntry>> watchEntriesForHabit(String habitId) {
    return (_db.select(_db.habitEntries)
          ..where((e) => e.habitId.equals(habitId))
          ..orderBy([(e) => drift.OrderingTerm.desc(e.date)]))
        .watch();
  }

  Future<String> addHabit(
    String title, {
    String subtitle = '',
    String? category,
    int priority = 0,
    String frequencyType = 'daily',
    List<int>? daysOfWeek,
    int? intervalDays,
    int? targetPerPeriod,
    DateTime? reminderTime,
    DateTime? startDate,
    DateTime? endDate,
    double? goalTarget,
    String? goalUnit,
    String? notes,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.habits).insert(HabitsCompanion.insert(
          id: id,
          title: title,
          subtitle: drift.Value(subtitle),
          category: drift.Value(category),
          priority: drift.Value(priority),
          frequencyType: drift.Value(frequencyType),
          daysOfWeek: drift.Value(daysOfWeek == null || daysOfWeek.isEmpty ? null : daysOfWeek.join(',')),
          intervalDays: drift.Value(intervalDays),
          targetPerPeriod: drift.Value(targetPerPeriod),
          reminderTime: drift.Value(reminderTime),
          startDate: drift.Value(startDate ?? dateOnly(DateTime.now())),
          endDate: drift.Value(endDate),
          goalTarget: drift.Value(goalTarget),
          goalUnit: drift.Value(goalUnit),
          notes: drift.Value(notes),
        ));
    return id;
  }

  Future<void> updateHabit(
    String id, {
    required String title,
    String subtitle = '',
    String? category,
    int priority = 0,
    required String frequencyType,
    List<int>? daysOfWeek,
    int? intervalDays,
    int? targetPerPeriod,
    DateTime? reminderTime,
    DateTime? startDate,
    DateTime? endDate,
    double? goalTarget,
    String? goalUnit,
    String? notes,
  }) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        title: drift.Value(title),
        subtitle: drift.Value(subtitle),
        category: drift.Value(category),
        priority: drift.Value(priority),
        frequencyType: drift.Value(frequencyType),
        daysOfWeek: drift.Value(daysOfWeek == null || daysOfWeek.isEmpty ? null : daysOfWeek.join(',')),
        intervalDays: drift.Value(intervalDays),
        targetPerPeriod: drift.Value(targetPerPeriod),
        reminderTime: drift.Value(reminderTime),
        startDate: drift.Value(startDate),
        endDate: drift.Value(endDate),
        goalTarget: drift.Value(goalTarget),
        goalUnit: drift.Value(goalUnit),
        notes: drift.Value(notes),
      ),
    );
    await _syncStoredStreak(id);
  }

  Future<void> setArchived(String id, bool archived) async {
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(archived: drift.Value(archived)),
    );
  }

  Future<void> deleteHabit(String id) async {
    await (_db.delete(_db.habitEntries)..where((e) => e.habitId.equals(id))).go();
    await (_db.delete(_db.habits)..where((h) => h.id.equals(id))).go();
  }

  /// Legacy quick-complete used by the Home screen's "Today" list, which has
  /// no notion of a specific date. Kept so Home keeps compiling/behaving as
  /// before; it now also logs a real entry for today so the habit's
  /// calendar/statistics stay accurate even from that surface.
  Future<void> incrementStreak(String id, int currentStreak, double currentProgress) async {
    final newStreak = currentStreak + 1;
    final newProgress = (newStreak / 21).clamp(0.0, 1.0);
    await (_db.update(_db.habits)..where((h) => h.id.equals(id))).write(
      HabitsCompanion(
        streak: drift.Value(newStreak),
        progress: drift.Value(newProgress),
      ),
    );
    await upsertEntry(id, DateTime.now(), isDone: true);
  }

  /// Toggles today-or-any-day's log: if a done entry already exists for
  /// [date] it is removed (un-done), otherwise one is created. This is the
  /// primary write path for the redesigned habit screens.
  Future<void> toggleEntry(String habitId, DateTime date) async {
    final day = dateOnly(date);
    final existing = await (_db.select(_db.habitEntries)
          ..where((e) => e.habitId.equals(habitId) & e.date.equals(day)))
        .getSingleOrNull();
    if (existing != null) {
      await (_db.delete(_db.habitEntries)..where((e) => e.id.equals(existing.id))).go();
    } else {
      await _db.into(_db.habitEntries).insert(HabitEntriesCompanion.insert(
            id: const Uuid().v4(),
            habitId: habitId,
            date: day,
            isDone: const drift.Value(true),
          ));
    }
    await _syncStoredStreak(habitId);
  }

  /// Logs (or updates) a specific quantified amount for [date] — e.g. "3
  /// miles" or "8 glasses" — and marks the day done whenever a value is
  /// supplied. Passing a null/zero value clears the entry.
  Future<void> upsertEntry(String habitId, DateTime date, {bool isDone = true, double? value, String? note}) async {
    final day = dateOnly(date);
    final existing = await (_db.select(_db.habitEntries)
          ..where((e) => e.habitId.equals(habitId) & e.date.equals(day)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.habitEntries).insert(HabitEntriesCompanion.insert(
            id: const Uuid().v4(),
            habitId: habitId,
            date: day,
            isDone: drift.Value(isDone),
            value: drift.Value(value),
            note: drift.Value(note),
          ));
    } else {
      await (_db.update(_db.habitEntries)..where((e) => e.id.equals(existing.id))).write(
        HabitEntriesCompanion(
          isDone: drift.Value(isDone),
          value: drift.Value(value),
          note: drift.Value(note),
        ),
      );
    }
    await _syncStoredStreak(habitId);
  }

  Future<void> clearEntry(String habitId, DateTime date) async {
    final day = dateOnly(date);
    await (_db.delete(_db.habitEntries)..where((e) => e.habitId.equals(habitId) & e.date.equals(day))).go();
    await _syncStoredStreak(habitId);
  }

  /// Recomputes the current streak from the real entry log and mirrors it
  /// onto `habits.streak`/`habits.progress` so older surfaces (Home,
  /// Analytics) that only read the stored columns stay reasonably in sync.
  Future<void> _syncStoredStreak(String habitId) async {
    final habit = await getHabitById(habitId);
    if (habit == null) return;
    final entries = await (_db.select(_db.habitEntries)..where((e) => e.habitId.equals(habitId))).get();
    final doneDays = entries.where((e) => e.isDone).map((e) => dateOnly(e.date)).toSet();
    final streak = currentStreakFor(habit, doneDays);
    await (_db.update(_db.habits)..where((h) => h.id.equals(habitId))).write(
      HabitsCompanion(
        streak: drift.Value(streak),
        progress: drift.Value((streak / 21).clamp(0.0, 1.0)),
      ),
    );
  }
}

/// Whether [habit] is scheduled to happen on calendar day [day], based on
/// its frequency settings and start/end date. Shared by the streak/stats
/// math and by the UI (to grey out non-scheduled days).
bool isHabitScheduled(Habit habit, DateTime day) {
  final d = dateOnly(day);
  final start = habit.startDate == null ? null : dateOnly(habit.startDate!);
  final end = habit.endDate == null ? null : dateOnly(habit.endDate!);
  if (start != null && d.isBefore(start)) return false;
  if (end != null && d.isAfter(end)) return false;

  switch (habit.frequencyType) {
    case 'specificDays':
      if (habit.daysOfWeek == null || habit.daysOfWeek!.isEmpty) return true;
      final days = habit.daysOfWeek!.split(',').map(int.parse).toSet();
      return days.contains(d.weekday - 1); // 0=Mon..6=Sun
    case 'interval':
      final base = start ?? d;
      final interval = habit.intervalDays ?? 2;
      return d.difference(base).inDays % interval == 0;
    case 'daily':
    default:
      return true;
  }
}

/// Current streak (consecutive scheduled days completed, walking backward
/// from today) computed purely from the logged entry days.
int currentStreakFor(Habit habit, Set<DateTime> doneDays) {
  final today = dateOnly(DateTime.now());
  var streak = 0;
  var cursor = today;
  // A habit not yet due today (e.g. logged yesterday, not today) shouldn't
  // reset to zero the moment the clock ticks past midnight — so if today is
  // scheduled but not done yet, start counting from yesterday instead.
  if (isHabitScheduled(habit, cursor) && !doneDays.contains(cursor)) {
    cursor = cursor.subtract(const Duration(days: 1));
  }
  final start = habit.startDate == null ? null : dateOnly(habit.startDate!);
  while (start == null || !cursor.isBefore(start)) {
    if (!isHabitScheduled(habit, cursor)) {
      cursor = cursor.subtract(const Duration(days: 1));
      continue;
    }
    if (!doneDays.contains(cursor)) break;
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  return streak;
}

/// Longest streak ever recorded for [habit] given its full set of done days.
int bestStreakFor(Habit habit, Set<DateTime> doneDays) {
  if (doneDays.isEmpty) return 0;
  final sorted = doneDays.toList()..sort();
  var best = 0;
  var running = 0;
  DateTime? prevScheduled;
  final start = habit.startDate == null ? null : dateOnly(habit.startDate!);
  final rangeStart = start ?? sorted.first;
  final rangeEnd = sorted.last;
  for (var d = rangeStart; !d.isAfter(rangeEnd); d = d.add(const Duration(days: 1))) {
    if (!isHabitScheduled(habit, d)) continue;
    if (doneDays.contains(d)) {
      running = (prevScheduled == null) ? 1 : running + 1;
      best = running > best ? running : best;
    } else {
      running = 0;
    }
    prevScheduled = d;
  }
  return best;
}

/// Completion rate over the trailing [days] scheduled days, 0..1.
double completionRateFor(Habit habit, Set<DateTime> doneDays, {int days = 30}) {
  final today = dateOnly(DateTime.now());
  var scheduled = 0;
  var done = 0;
  for (var i = 0; i < days; i++) {
    final d = today.subtract(Duration(days: i));
    if (!isHabitScheduled(habit, d)) continue;
    scheduled++;
    if (doneDays.contains(d)) done++;
  }
  if (scheduled == 0) return 0;
  return done / scheduled;
}
