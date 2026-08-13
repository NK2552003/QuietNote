import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final journalRepositoryProvider = Provider<JournalRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return JournalRepository(db);
});

final journalStreamProvider = StreamProvider<List<JournalData>>((ref) {
  final repo = ref.watch(journalRepositoryProvider);
  return repo.watchAllEntries();
});

class JournalRepository {
  final AppDatabase _db;
  JournalRepository(this._db);

  Stream<List<JournalData>> watchAllEntries() {
    return (_db.select(
      _db.journal,
    )..orderBy([(j) => drift.OrderingTerm.desc(j.createdAt)])).watch();
  }

  Future<void> addEntry(
    String entry, {
    String? mood,
    String? title,
    List<String> tags = const [],
  }) async {
    await _db
        .into(_db.journal)
        .insert(
          JournalCompanion.insert(
            id: const Uuid().v4(),
            title: drift.Value(
              title?.trim().isEmpty ?? true ? 'Untitled entry' : title!.trim(),
            ),
            entry: entry,
            mood: drift.Value(mood),
            tags: drift.Value(tagsToCsv(tags)),
          ),
        );
  }

  Future<JournalData?> getEntry(String id) {
    return (_db.select(
      _db.journal,
    )..where((j) => j.id.equals(id))).getSingleOrNull();
  }

  /// Distinct tags currently in use across all journal entries, for building
  /// a filter bar on the list screen.
  Stream<List<String>> watchTagsInUse() {
    return watchAllEntries().map(
      (entries) => distinctTagsInUse(entries.map((e) => e.tags)),
    );
  }

  Future<void> deleteEntry(String id) async {
    await (_db.delete(_db.journal)..where((j) => j.id.equals(id))).go();
    // Clean up any attached images so they don't linger as orphaned files
    // and rows once their entry is gone.
    await (_db.delete(
          _db.attachments,
        )..where((a) => a.parentId.equals(id) & a.parentType.equals('journal')))
        .go();
  }
}
