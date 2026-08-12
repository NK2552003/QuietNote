import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:quietnote/core/settings/app_settings.dart';

/// Key/value persistence for [AppSettings] inside the app's existing SQLite
/// database. The table is created on demand with plain SQL, so the generated
/// Drift code (`database.g.dart`) stays exactly as it is.
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  static const String _table = 'app_settings';

  Future<void> _ensureTable() async {
    await _db.customStatement(
      'CREATE TABLE IF NOT EXISTS $_table ('
      'key TEXT NOT NULL PRIMARY KEY, '
      'value TEXT NOT NULL)',
    );
  }

  Future<AppSettings> load() async {
    await _ensureTable();
    final List<QueryRow> rows =
        await _db.customSelect('SELECT key, value FROM $_table').get();
    final Map<String, String> map = <String, String>{
      for (final QueryRow row in rows)
        row.read<String>('key'): row.read<String>('value'),
    };
    return AppSettings.fromMap(map);
  }

  Future<void> save(AppSettings settings) async {
    await _ensureTable();
    await _db.transaction(() async {
      for (final MapEntry<String, String> entry in settings.toMap().entries) {
        await _db.customStatement(
          'INSERT INTO $_table (key, value) VALUES (?, ?) '
          'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
          <Object?>[entry.key, entry.value],
        );
      }
    });
  }

  Future<void> reset() async {
    await _ensureTable();
    await _db.customStatement('DELETE FROM $_table');
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((Ref ref) {
  return SettingsRepository(ref.watch(databaseProvider));
});

/// App-wide settings state. Reads once on start, writes through on change so
/// every screen (theme, text size, reminders) reacts instantly.
final settingsProvider =
    AsyncNotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends AsyncNotifier<AppSettings> {
  SettingsRepository get _repo => ref.read(settingsRepositoryProvider);

  @override
  Future<AppSettings> build() => _repo.load();

  @override
  Future<AppSettings> update(
    FutureOr<AppSettings> Function(AppSettings current) cb, {
    FutureOr<AppSettings> Function(Object error, StackTrace stackTrace)? onError,
  }) async {
    final AppSettings current = state.value ?? const AppSettings();
    final AppSettings next = await cb(current);
    state = AsyncData<AppSettings>(next);
    await _repo.save(next);
    return next;
  }

  Future<void> resetToDefaults() async {
    await _repo.reset();
    state = const AsyncData<AppSettings>(AppSettings());
  }
}
