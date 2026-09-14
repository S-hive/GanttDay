import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../domain/gantt/argb_color.dart';
import '../../domain/gantt/color_palette.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/models/color_swatch.dart';

const _customSwatchName = '自定义色';

Future<void> seedFactorySwatches(DatabaseExecutor db) async {
  for (final s in kFactoryColorSwatches) {
    await _insertSwatch(db, s);
  }
}

Future<void> _insertSwatch(DatabaseExecutor db, ColorSwatch s) async {
  await db.insert('color_swatch', {
    'id': s.id,
    'name': s.name,
    'argb': s.argb,
    'hue': s.hue,
    'saturation': s.saturation,
    'lightness': s.lightness,
    'is_default': s.isDefault ? 1 : 0,
    'sort_order': s.sortOrder,
    'slate': s.slate ? 1 : 0,
  });
}

/// Migrates schema 1 (integer hue columns) to schema 2 (swatch ids + color_swatch).
Future<void> migrateV1toV2(DatabaseExecutor db) async {
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
  await seedFactorySwatches(db);

  final migrator = _HueToSwatchMigrator(db);

  await db.execute('ALTER TABLE tag ADD COLUMN swatch_id TEXT');
  final tags = await db.query('tag');
  for (final row in tags) {
    final id = row['id'] as String;
    final hue = row['hue'] as int;
    final swatchId = await migrator.resolve(hue);
    await db.update('tag', {'swatch_id': swatchId}, where: 'id = ?', whereArgs: [id]);
  }

  await db.execute('ALTER TABLE task ADD COLUMN auto_swatch_id TEXT');
  await db.execute('ALTER TABLE task ADD COLUMN override_swatch_id TEXT');
  final tasks = await db.query('task');
  for (final row in tasks) {
    final id = row['id'] as String;
    final autoId = await migrator.resolve(row['auto_hue'] as int);
    final overrideHue = row['override_hue'] as int?;
    final overrideId =
        overrideHue != null ? await migrator.resolve(overrideHue) : null;
    await db.update(
      'task',
      {'auto_swatch_id': autoId, 'override_swatch_id': overrideId},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  await _rebuildTagTable(db);
  await _rebuildTaskTable(db);
}

/// Migrates schema 2 (shared color_swatch FKs) to schema 3 (tag ARGB + default_color).
Future<void> migrateV2toV3(DatabaseExecutor db) async {
  Future<void> body(DatabaseExecutor txn) async {
    await txn.execute('''
      CREATE TABLE default_color (
        id TEXT PRIMARY KEY,
        argb INTEGER NOT NULL,
        is_current INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    final defaults = await txn.query(
      'color_swatch',
      where: 'is_default = 1',
      orderBy: 'sort_order ASC',
      limit: 1,
    );
    final defaultArgb =
        defaults.isEmpty ? kFallbackArgb : defaults.first['argb'] as int;
    await txn.insert('default_color', {
      'id': const Uuid().v4(),
      'argb': defaultArgb,
      'is_current': 1,
      'sort_order': 0,
    });

    await txn.execute('ALTER TABLE tag ADD COLUMN argb INTEGER');
    await txn.execute('ALTER TABLE tag ADD COLUMN sort_order INTEGER');
    await txn.execute('''
      UPDATE tag SET argb = (
        SELECT color_swatch.argb FROM color_swatch
        WHERE color_swatch.id = tag.swatch_id
      )
    ''');
    await txn.execute(
      'UPDATE tag SET argb = ? WHERE argb IS NULL',
      [kFallbackArgb],
    );
    await txn.execute(
      'UPDATE tag SET sort_order = rowid WHERE sort_order IS NULL',
    );

    await txn.execute('''
      CREATE TABLE tag_new (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        argb INTEGER NOT NULL,
        sort_order INTEGER NOT NULL
      )
    ''');
    await txn.execute('''
      INSERT INTO tag_new (id, name, argb, sort_order)
      SELECT id, name, argb, sort_order FROM tag
    ''');
    await txn.execute('DROP TABLE tag');
    await txn.execute('ALTER TABLE tag_new RENAME TO tag');

    await txn.execute('''
      CREATE TABLE task_new (
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
    await txn.execute('''
      INSERT INTO task_new (
        id, title, planned_start, planned_end, actual_start, actual_end,
        is_done, tag_id, override_argb, notes, created_at
      )
      SELECT
        t.id, t.title, t.planned_start, t.planned_end, t.actual_start, t.actual_end,
        t.is_done,
        CASE
          WHEN t.primary_tag_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM tag WHERE tag.id = t.primary_tag_id
          ) THEN t.primary_tag_id
          ELSE NULL
        END,
        (SELECT cs.argb FROM color_swatch cs WHERE cs.id = t.override_swatch_id),
        t.notes, t.created_at
      FROM task t
    ''');
    await txn.execute('DROP TABLE task');
    await txn.execute('ALTER TABLE task_new RENAME TO task');
    await txn.execute(
        'CREATE INDEX idx_task_planned_start ON task(planned_start)');
    await txn.execute('CREATE INDEX idx_task_planned_end ON task(planned_end)');

    await txn.execute('DROP TABLE task_tag');
    await txn.execute('DROP TABLE color_swatch');
  }

  if (db is Database) {
    await db.transaction(body);
  } else {
    await body(db);
  }
}

Future<void> _rebuildTagTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE tag_new (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL UNIQUE,
      swatch_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    INSERT INTO tag_new (id, name, swatch_id)
    SELECT id, name, swatch_id FROM tag
  ''');
  await db.execute('DROP TABLE tag');
  await db.execute('ALTER TABLE tag_new RENAME TO tag');
}

Future<void> _rebuildTaskTable(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE task_new (
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
  await db.execute('''
    INSERT INTO task_new (
      id, title, planned_start, planned_end, actual_start, actual_end,
      is_done, primary_tag_id, auto_swatch_id, override_swatch_id, notes, created_at
    )
    SELECT
      id, title, planned_start, planned_end, actual_start, actual_end,
      is_done, primary_tag_id, auto_swatch_id, override_swatch_id, notes, created_at
    FROM task
  ''');
  await db.execute('DROP TABLE task');
  await db.execute('ALTER TABLE task_new RENAME TO task');
  await db.execute(
      'CREATE INDEX idx_task_planned_start ON task(planned_start)');
  await db.execute('CREATE INDEX idx_task_planned_end ON task(planned_end)');
}

class _HueToSwatchMigrator {
  _HueToSwatchMigrator(this._db) {
    for (final s in kFactoryColorSwatches) {
      _hueToId[s.hue] = s.id;
    }
  }

  final DatabaseExecutor _db;
  final _uuid = const Uuid();
  final Map<int, String> _hueToId = {};
  var _nextSortOrder = kFactoryColorSwatches.length;

  Future<String> resolve(int hue) async {
    final cached = _hueToId[hue];
    if (cached != null) return cached;

    final id = _uuid.v4();
    final argb = ArgbColor.fromHsl(
      hue.toDouble(),
      kPalettePreviewSaturation,
      kPalettePreviewLightness,
    );
    final hsl = ArgbColor.toHsl(argb);
    final swatch = ColorSwatch(
      id: id,
      name: _customSwatchName,
      argb: argb,
      hue: hsl.hue.round() % 360,
      saturation: hsl.saturation,
      lightness: hsl.lightness,
      sortOrder: _nextSortOrder++,
    );
    await _insertSwatch(_db, swatch);
    _hueToId[hue] = id;
    return id;
  }
}
