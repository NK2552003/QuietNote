import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabase {
  LocalDatabase._();
  static final instance = LocalDatabase._();
  Database? _database;

  Future<Database> get database async => _database ??= await _open();

  Future<Database> _open() async {
    final root = await getDatabasesPath();
    return openDatabase(join(root, 'quietnote.db'), version: 1, onCreate: (db, _) async {
      await db.execute('CREATE TABLE captures (id INTEGER PRIMARY KEY AUTOINCREMENT, text TEXT NOT NULL, kind TEXT NOT NULL, completed INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL)');
    });
  }

  Future<int> insertCapture({required String text, required String kind}) async {
    final db = await database;
    return db.insert('captures', {'text': text, 'kind': kind, 'created_at': DateTime.now().millisecondsSinceEpoch});
  }

  Future<List<Map<String, Object?>>> captures() async => (await database).query('captures', orderBy: 'created_at DESC');
  Future<void> setCompleted(int id, bool value) async => (await database).update('captures', {'completed': value ? 1 : 0}, where: 'id = ?', whereArgs: [id]);
}
