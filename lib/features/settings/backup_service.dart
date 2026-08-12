import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:quietnote/core/database/database.dart';
import 'package:quietnote/core/database/database_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// Result of a non-destructive merge import.
class MergeReport {
  MergeReport();

  final Map<String, int> added = <String, int>{};
  final Map<String, int> updated = <String, int>{};
  final Map<String, int> skipped = <String, int>{};
  final List<String> warnings = <String>[];

  int get totalAdded => added.values.fold(0, (int a, int b) => a + b);
  int get totalUpdated => updated.values.fold(0, (int a, int b) => a + b);
  int get totalSkipped => skipped.values.fold(0, (int a, int b) => a + b);

  void bump(Map<String, int> bucket, String table) =>
      bucket[table] = (bucket[table] ?? 0) + 1;

  List<String> get changedTables {
    final Set<String> names = <String>{...added.keys, ...updated.keys};
    final List<String> list = names
        .where((String t) => (added[t] ?? 0) + (updated[t] ?? 0) > 0)
        .toList()
      ..sort();
    return list;
  }
}

/// Summary shown before a merge runs.
class BackupPreview {
  const BackupPreview({required this.fileName, required this.sizeBytes, required this.counts});

  final String fileName;
  final int sizeBytes;
  final Map<String, int> counts;

  int get totalRows => counts.values.fold(0, (int a, int b) => a + b);
}

class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  /// Tables merged from a backup, mapped to the column used to decide which
  /// copy is newer. `null` means "never overwrite an existing row".
  static const Map<String, String?> _tables = <String, String?>{
    'habits': null,
    'habit_entries': 'created_at',
    'tasks': null,
    'notes': 'created_at',
    'journal': 'created_at',
    'goals': null,
    'routines': null,
    'calendar_events': null,
    'attachments': 'created_at',
  };

  static const Map<String, String> tableLabels = <String, String>{
    'habits': 'Habits',
    'habit_entries': 'Habit check-ins',
    'tasks': 'To-dos',
    'notes': 'Notes',
    'journal': 'Journal entries',
    'goals': 'Goals',
    'routines': 'Routines',
    'calendar_events': 'Calendar events',
    'attachments': 'Attachments',
  };

  Future<File> databaseFile() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'db.sqlite'));
  }

  /// Row counts of the live database, for the storage panel.
  Future<Map<String, int>> liveCounts() async {
    final Map<String, int> counts = <String, int>{};
    for (final String table in _tables.keys) {
      try {
        final QueryRow row = await _db
            .customSelect('SELECT COUNT(*) AS c FROM $table')
            .getSingle();
        counts[table] = row.read<int>('c');
      } catch (_) {
        counts[table] = 0;
      }
    }
    return counts;
  }

  Future<BackupPreview> inspect(String path) async {
    final File file = File(path);
    final sqflite.Database backup =
        await sqflite.openReadOnlyDatabase(path);
    try {
      final Set<String> present = await _backupTables(backup);
      if (!present.contains('notes') && !present.contains('habits')) {
        throw const FormatException(
          'This file does not look like a QuietNote backup.',
        );
      }
      final Map<String, int> counts = <String, int>{};
      for (final String table in _tables.keys) {
        if (!present.contains(table)) continue;
        final List<Map<String, Object?>> rows =
            await backup.rawQuery('SELECT COUNT(*) AS c FROM $table');
        counts[table] = (rows.first['c'] as int?) ?? 0;
      }
      return BackupPreview(
        fileName: p.basename(path),
        sizeBytes: await file.length(),
        counts: counts,
      );
    } finally {
      await backup.close();
    }
  }

  /// Merges a backup into the live database. Rows are only ever inserted or
  /// refreshed — nothing is deleted and the live database file is never
  /// replaced.
  Future<MergeReport> merge(String path) async {
    final MergeReport report = MergeReport();
    final sqflite.Database backup = await sqflite.openReadOnlyDatabase(path);
    try {
      final Set<String> present = await _backupTables(backup);

      for (final MapEntry<String, String?> entry in _tables.entries) {
        final String table = entry.key;
        final String? stampColumn = entry.value;
        if (!present.contains(table)) {
          report.warnings.add('${tableLabels[table] ?? table}: not in backup');
          continue;
        }

        final Set<String> liveColumns = await _liveColumns(table);
        final Set<String> backupColumns = await _backupColumns(backup, table);
        final List<String> shared = liveColumns
            .intersection(backupColumns)
            .toList()
          ..sort();
        if (!shared.contains('id')) {
          report.warnings.add('${tableLabels[table] ?? table}: incompatible, skipped');
          continue;
        }
        if (backupColumns.difference(liveColumns).isNotEmpty) {
          report.warnings.add(
            '${tableLabels[table] ?? table}: some backup fields are from a newer version and were ignored',
          );
        }

        final List<Map<String, Object?>> rows = await backup.query(table);
        for (final Map<String, Object?> row in rows) {
          final Object? id = row['id'];
          if (id == null) continue;

          final QueryRow? existing = await _db
              .customSelect(
                'SELECT * FROM $table WHERE id = ? LIMIT 1',
                variables: <Variable<Object>>[Variable<Object>(id)],
              )
              .getSingleOrNull();

          if (existing == null) {
            final List<String> cols =
                shared.where((String c) => row.containsKey(c)).toList();
            final String placeholders =
                List<String>.filled(cols.length, '?').join(', ');
            await _db.customStatement(
              'INSERT OR IGNORE INTO $table (${cols.join(', ')}) VALUES ($placeholders)',
              <Object?>[for (final String c in cols) row[c]],
            );
            report.bump(report.added, table);
            continue;
          }

          if (stampColumn == null || !shared.contains(stampColumn)) {
            report.bump(report.skipped, table);
            continue;
          }

          final int backupStamp = _asMillis(row[stampColumn]);
          final int liveStamp = _asMillis(existing.data[stampColumn]);
          if (backupStamp <= liveStamp) {
            report.bump(report.skipped, table);
            continue;
          }

          final List<String> cols = shared
              .where((String c) => c != 'id' && row.containsKey(c))
              .toList();
          if (cols.isEmpty) {
            report.bump(report.skipped, table);
            continue;
          }
          final String assignments =
              cols.map((String c) => '$c = ?').join(', ');
          await _db.customStatement(
            'UPDATE $table SET $assignments WHERE id = ?',
            <Object?>[for (final String c in cols) row[c], id],
          );
          report.bump(report.updated, table);
        }
      }
    } finally {
      await backup.close();
    }
    return report;
  }

  Future<Set<String>> _backupTables(sqflite.Database backup) async {
    final List<Map<String, Object?>> rows = await backup.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    return rows.map((Map<String, Object?> r) => '${r['name']}').toSet();
  }

  Future<Set<String>> _backupColumns(
    sqflite.Database backup,
    String table,
  ) async {
    final List<Map<String, Object?>> rows =
        await backup.rawQuery('PRAGMA table_info($table)');
    return rows.map((Map<String, Object?> r) => '${r['name']}').toSet();
  }

  Future<Set<String>> _liveColumns(String table) async {
    final List<QueryRow> rows =
        await _db.customSelect('PRAGMA table_info($table)').get();
    return rows.map((QueryRow r) => r.read<String>('name')).toSet();
  }

  static int _asMillis(Object? value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      final DateTime? parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.millisecondsSinceEpoch;
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }
}

final backupServiceProvider = Provider<BackupService>((Ref ref) {
  return BackupService(ref.watch(databaseProvider));
});

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
