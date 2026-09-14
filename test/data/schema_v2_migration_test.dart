import 'package:ganttday/data/sqlite/swatch_migration.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

Future<List<String>> _columnNames(Database db, String table) async {
  final info = await db.rawQuery('PRAGMA table_info($table)');
  return info.map((r) => r['name'] as String).toList();
}

/// V1 schema (hue columns) for migration tests.
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

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('migrateV1toV2 maps factory hues and creates custom swatches', () async {
    final db = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1),
    );
    await _createV1Schema(db);

    await db.insert('tag', {'id': 'tg-peach', 'name': 'peach', 'hue': 24});
    await db.insert('tag', {'id': 'tg-custom', 'name': 'custom', 'hue': 999});

    await db.insert('task', {
      'id': 't1',
      'title': 'peach primary',
      'planned_start': 100,
      'planned_end': 200,
      'is_done': 0,
      'primary_tag_id': 'tg-peach',
      'auto_hue': 218,
      'override_hue': null,
      'created_at': 1,
    });
    await db.insert('task', {
      'id': 't2',
      'title': 'orphan custom',
      'planned_start': 300,
      'planned_end': 400,
      'is_done': 0,
      'auto_hue': 333,
      'override_hue': null,
      'created_at': 2,
    });

    await migrateV1toV2(db);

    final swatches = await db.query('color_swatch', orderBy: 'sort_order ASC');
    expect(swatches.length, greaterThanOrEqualTo(10));

    final swatchIds = swatches.map((r) => r['id'] as String).toSet();
    for (final f in kFactoryColorSwatches) {
      expect(swatchIds, contains(f.id));
    }

    final customSwatches =
        swatches.where((r) => r['name'] == '自定义色').toList();
    expect(customSwatches.length, 2);

    final tags = await db.query('tag');
    expect(await _columnNames(db, 'tag'), isNot(contains('hue')));
    expect(
      tags.firstWhere((t) => t['id'] == 'tg-peach')['swatch_id'],
      'peach',
    );
    final customTagSwatchId =
        tags.firstWhere((t) => t['id'] == 'tg-custom')['swatch_id'] as String;
    expect(customTagSwatchId, isNot('peach'));

    final tasks = await db.query('task');
    expect(await _columnNames(db, 'task'), isNot(contains('auto_hue')));
    expect(await _columnNames(db, 'task'), isNot(contains('override_hue')));

    final t1 = tasks.firstWhere((t) => t['id'] == 't1');
    expect(t1['auto_swatch_id'], 'azure');
    expect(t1['override_swatch_id'], isNull);

    final t2SwatchId =
        tasks.firstWhere((t) => t['id'] == 't2')['auto_swatch_id'] as String;
    expect(t2SwatchId, isNot('azure'));
    expect(t2SwatchId, isNot(customTagSwatchId));

    await db.close();
  });
}
