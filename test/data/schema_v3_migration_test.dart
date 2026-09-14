import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/swatch_migration.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

Future<List<String>> _columnNames(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => r['name'] as String).toList();
}

Future<bool> _tableExists(Database db, String name) async {
  final rows = await db.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [name],
  );
  return rows.isNotEmpty;
}

/// V1 schema (hue columns) for upgrade-through-v2 tests.
Future<void> _createV1Schema(DatabaseExecutor db) async {
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
      auto_hue INTEGER NOT NULL,
      override_hue INTEGER,
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
      hue INTEGER NOT NULL
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

/// Schema 2 tables for migrateV2toV3 fixtures.
Future<void> _createV2Schema(DatabaseExecutor db) async {
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('AppDatabase.open fresh creates schema 3 with one 霁蓝 default_color',
      () async {
    const path = 'v3_fresh_open.db';
    await databaseFactory.deleteDatabase(path);
    Database? db;
    try {
      db = await AppDatabase.open(databaseFactory, path);

      expect(AppDatabase.schemaVersion, 3);
      expect(await _tableExists(db, 'color_swatch'), isFalse);
      expect(await _tableExists(db, 'task_tag'), isFalse);
      expect(await _tableExists(db, 'default_color'), isTrue);

      final tagCols = await _columnNames(db, 'tag');
      expect(tagCols, contains('argb'));
      expect(tagCols, contains('sort_order'));
      expect(tagCols, isNot(contains('swatch_id')));
      expect(await db.query('tag'), isEmpty);

      final taskCols = await _columnNames(db, 'task');
      expect(taskCols, contains('tag_id'));
      expect(taskCols, contains('override_argb'));
      expect(taskCols, isNot(contains('auto_swatch_id')));
      expect(taskCols, isNot(contains('primary_tag_id')));
      expect(taskCols, isNot(contains('override_swatch_id')));

      final defaults = await db.query('default_color');
      expect(defaults, hasLength(1));
      expect(defaults.single['argb'], kFallbackArgb);
      expect(defaults.single['argb'], 0xFF457BD9);
      expect(defaults.single['is_current'], 1);
      expect(defaults.single['sort_order'], 0);
      expect(defaults.single['id'], isNotEmpty);
    } finally {
      await db?.close();
      await databaseFactory.deleteDatabase(path);
    }
  });

  test('migrateV2toV3 copies shared azure onto both tags and drops v2 tables',
      () async {
    const path = 'v3_migrate_v2.db';
    await databaseFactory.deleteDatabase(path);
    final db = await databaseFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: 2, singleInstance: false),
    );
    addTearDown(() async {
      await db.close();
      await databaseFactory.deleteDatabase(path);
    });
    await _createV2Schema(db);

    await db.insert('color_swatch', {
      'id': 'azure',
      'name': '霁蓝',
      'argb': 0xFF457BD9,
      'hue': 218,
      'saturation': 0.661,
      'lightness': 0.561,
      'is_default': 1,
      'sort_order': 0,
      'slate': 0,
    });
    await db.insert('color_swatch', {
      'id': 'peach',
      'name': '桃',
      'argb': 0xFFFFDAC1,
      'hue': 24,
      'saturation': 1.0,
      'lightness': 0.878,
      'is_default': 0,
      'sort_order': 1,
      'slate': 0,
    });

    await db.insert('tag', {
      'id': 'tg-a',
      'name': 'work',
      'swatch_id': 'azure',
    });
    await db.insert('tag', {
      'id': 'tg-b',
      'name': 'study',
      'swatch_id': 'azure',
    });

    await db.insert('task', {
      'id': 't-primary',
      'title': 'has primary and extra',
      'planned_start': 100,
      'planned_end': 200,
      'is_done': 0,
      'primary_tag_id': 'tg-a',
      'auto_swatch_id': 'azure',
      'created_at': 1,
    });
    await db.insert('task_tag', {'task_id': 't-primary', 'tag_id': 'tg-a'});
    await db.insert('task_tag', {'task_id': 't-primary', 'tag_id': 'tg-b'});

    await db.insert('task', {
      'id': 't-override',
      'title': 'has override',
      'planned_start': 300,
      'planned_end': 400,
      'is_done': 0,
      'auto_swatch_id': 'azure',
      'override_swatch_id': 'peach',
      'created_at': 2,
    });

    await migrateV2toV3(db);

    final tags = await db.query('tag');
    expect(tags, hasLength(2));
    expect(await _columnNames(db, 'tag'), contains('argb'));
    expect(await _columnNames(db, 'tag'), isNot(contains('swatch_id')));
    expect(
      tags.firstWhere((t) => t['id'] == 'tg-a')['argb'],
      0xFF457BD9,
    );
    expect(
      tags.firstWhere((t) => t['id'] == 'tg-b')['argb'],
      0xFF457BD9,
    );

    final tasks = await db.query('task');
    final primary = tasks.firstWhere((t) => t['id'] == 't-primary');
    expect(primary['tag_id'], 'tg-a');
    expect(await _columnNames(db, 'task'), isNot(contains('primary_tag_id')));
    expect(await _columnNames(db, 'task'), isNot(contains('auto_swatch_id')));

    final overridden = tasks.firstWhere((t) => t['id'] == 't-override');
    expect(overridden['override_argb'], 0xFFFFDAC1);
    expect(overridden['tag_id'], isNull);

    final defaults = await db.query('default_color');
    expect(defaults, hasLength(1));
    expect(defaults.single['argb'], 0xFF457BD9);
    expect(defaults.single['is_current'], 1);

    expect(await _tableExists(db, 'color_swatch'), isFalse);
    expect(await _tableExists(db, 'task_tag'), isFalse);
  });

  test('AppDatabase.open upgrades v1 through v2 to schema 3', () async {
    const path = 'v1_to_v3_upgrade_test.db';
    await databaseFactory.deleteDatabase(path);
    Database? db;
    try {
      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) => _createV1Schema(db),
        ),
      );
      await v1.insert('tag', {'id': 'tg1', 'name': 'a', 'hue': 24});
      await v1.close();

      db = await AppDatabase.open(databaseFactory, path);
      expect(await _columnNames(db, 'tag'), contains('argb'));
      expect(await _columnNames(db, 'tag'), isNot(contains('swatch_id')));
      expect(await _columnNames(db, 'tag'), isNot(contains('hue')));
      expect((await db.query('tag')).single['argb'], 0xFFFFDAC1);
      expect(await _tableExists(db, 'color_swatch'), isFalse);
      expect(await _tableExists(db, 'task_tag'), isFalse);
      final defaults = await db.query('default_color');
      expect(defaults, hasLength(1));
      expect(defaults.single['argb'], kFallbackArgb);
      expect(defaults.single['is_current'], 1);
    } finally {
      await db?.close();
      await databaseFactory.deleteDatabase(path);
    }
  });
}
