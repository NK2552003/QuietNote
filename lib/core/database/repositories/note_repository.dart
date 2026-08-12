import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
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

  Future<void> addNote(String title, String content) async {
    await _db.into(_db.notes).insert(NotesCompanion.insert(
      id: const Uuid().v4(),
      title: title,
      content: content,
    ));
  }

  Future<Note?> getNoteById(String id) async {
    return (_db.select(_db.notes)..where((n) => n.id.equals(id))).getSingleOrNull();
  }

  Future<void> updateNote(String id, String title, String content) async {
    await (_db.update(_db.notes)..where((n) => n.id.equals(id))).write(
      NotesCompanion(
        title: drift.Value(title),
        content: drift.Value(content),
      ),
    );
  }

  Future<void> deleteNote(String id) async {
    await (_db.delete(_db.notes)..where((n) => n.id.equals(id))).go();
  }
}
