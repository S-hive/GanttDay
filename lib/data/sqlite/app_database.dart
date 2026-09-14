import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../domain/gantt/factory_swatches.dart';
import '../../platform/task_repository.dart' show DatabaseOpenException;
import 'swatch_migration.dart';

/// Opens the GanttDay database. On any open failure it throws
/// [DatabaseOpenException] — it never wipes or silently recreates the file
/// (spec section 8).
class AppDatabase {
  AppDatabase._();

  static const int schemaVersion = 3;

  static Future<Database> open(
    DatabaseFactory factory,
    String path,
  ) async {
    try {
      return await factory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onCreate: (db, version) async {
            await applySchema(db);
            await db.insert('default_color', {
              'id': const Uuid().v4(),
              'argb': kFallbackArgb,
              'is_current': 1,
              'sort_order': 0,
            });
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await migrateV1toV2(db);
            }
            if (oldVersion < 3) {
              await migrateV2toV3(db);
            }
          },
        ),
      );
    } catch (e) {
      throw DatabaseOpenException(e.toString(), path: path);
    }
  }

  static Future<void> applySchema(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE tag (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        argb INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE default_color (
        id TEXT PRIMARY KEY,
        argb INTEGER NOT NULL,
        is_current INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE task (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        planned_start INTEGER NOT NULL,
        planned_end INTEGER NOT NULL,
        actual_start INTEGER,
        actual_end INTEGER,
        is_done INTEGER NOT NULL DEFAULT 0,
        tag_id TEXT,
        override_argb INTEGER,
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_task_planned_start ON task(planned_start)');
    await db.execute('CREATE INDEX idx_task_planned_end ON task(planned_end)');
    await db.execute('''
      CREATE TABLE setting (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}
