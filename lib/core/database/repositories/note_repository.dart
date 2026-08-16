import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/utils/tag_utils.dart';
import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' as drift;

final noteRepositoryProvider = Provider<NoteRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return NoteRepository(db);
});

final notesStreamProvider = StreamProvider<List<Note>>((ref) {
  final repo = ref.watch(noteRepositoryProvider);
  return repo.watchAllNotes();
});

class NoteRepository {
  final AppDatabase _db;
  NoteRepository(this._db);

  Stream<List<Note>> watchAllNotes() {
    return (_db.select(_db.notes)
          ..orderBy([
            (t) => drift.OrderingTerm(expression: t.createdAt, mode: drift.OrderingMode.desc)
          ]))
        .watch();
  }

  Future<void> addNote(
    String title,
    String content, {
    List<String> tags = const [],
    String? courseId,
  }) async {
    await _db.into(_db.notes).insert(NotesCompanion.insert(
      id: const Uuid().v4(),
      title: title,
      content: content,
      tags: drift.Value(tagsToCsv(tags)),
      courseId: drift.Value(courseId),
    ));
  }

  Future<Note?> getNoteById(String id) async {
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  Future<void> updateNote(
    String id,
    String title,
    String content, {
    List<String>? tags,
    String? courseId,
  }) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: drift.Value(title),
        content: drift.Value(content),
        tags: tags != null
            ? drift.Value(tagsToCsv(tags))
            : const drift.Value.absent(),
        courseId: drift.Value(courseId),
      ),
    );
  }

  /// Distinct tags currently in use across all notes, for building a filter
  /// bar on the list screen.
  Stream<List<String>> watchTagsInUse() {
    return watchAllNotes().map(
      (notes) => distinctTagsInUse(notes.map((n) => n.tags)),
    );
  }

  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }
}
