import 'package:sqflite_common/sqlite_api.dart';

import '../../platform/task_repository.dart' show DatabaseOpenException;
import 'swatch_migration.dart';

/// Opens the GanttDay database. On any open failure it throws
/// [DatabaseOpenException] — it never wipes or silently recreates the file
/// (spec section 8).
class AppDatabase {
  AppDatabase._();

  static const int schemaVersion = 2;

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
            await seedFactorySwatches(db);
          },
          onUpgrade: (db, oldVersion, newVersion) async {
            if (oldVersion < 2) {
              await migrateV1toV2(db);
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
      CREATE TABLE color_swatch (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        argb INTEGER NOT NULL,
        hue INTEGER NOT NULL,
        saturation REAL NOT NULL,
        lightness REAL NOT NULL,
        is_default INTEGER NOT NULL,
        sort_order INTEGER NOT NULL,
        slate INTEGER NOT NULL DEFAULT 0
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
        primary_tag_id TEXT,
        auto_swatch_id TEXT NOT NULL,
        override_swatch_id TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_task_planned_start ON task(planned_start)');
    await db.execute('CREATE INDEX idx_task_planned_end ON task(planned_end)');
    await db.execute('''
      CREATE TABLE tag (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        swatch_id TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE task_tag (
        task_id TEXT NOT NULL,
        tag_id TEXT NOT NULL,
        PRIMARY KEY (task_id, tag_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE setting (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }
}
