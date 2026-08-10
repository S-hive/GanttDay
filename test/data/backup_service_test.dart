import 'dart:convert';

import 'package:ganttday/data/backup/backup_service.dart';
import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_settings_store.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
import 'package:ganttday/data/sqlite/swatch_migration.dart';
import 'package:ganttday/domain/gantt/swatch_resolve.dart';
import 'package:ganttday/domain/models/app_settings.dart';
import 'package:ganttday/domain/models/color_swatch.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SqliteTaskRepository repo;
  late SqliteSettingsStore settings;
  late BackupService backup;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.applySchema(db);
    await seedFactorySwatches(db);
    repo = SqliteTaskRepository(db);
    settings = SqliteSettingsStore(db);
    backup = BackupService(db, repo, settings);
  });

  tearDown(() async {
    await repo.dispose();
    await settings.dispose();
    await db.close();
  });

  Future<void> seed() async {
    await repo.upsertSwatch(const ColorSwatch(
      id: 'custom1',
      name: '自定义',
      argb: 0xFFAA5533,
      hue: 20,
      saturation: 0.6,
      lightness: 0.5,
      sortOrder: 8,
    ));
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', swatchId: 'leaf'));
    await repo.upsert(Task(
      id: 't1',
      title: 'clip',
      plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 9)),
      plannedEnd: WallClock.minutes(DateTime(2026, 8, 8, 11)),
      autoSwatchId: 'sky',
      overrideSwatchId: 'custom1',
      primaryTagId: 'tg1',
      createdAt: 1,
    ));
    await repo.setTaskTags('t1', ['tg1']);
    await settings.write(const AppSettings(
      visibleStartHour: 7,
      visibleEndHour: 21,
      urgencyWindowDays: 5,
    ));
  }

  test('round-trip export/import restores swatches tasks tags and settings', () async {
    await seed();
    final json = await backup.exportJson();
    final doc = jsonDecode(json) as Map<String, dynamic>;

    expect(doc['version'], 2);
    expect(doc['color_swatches'], isA<List>());
    final swatches = doc['color_swatches'] as List;
    expect(swatches.any((s) => s['id'] == 'custom1'), isTrue);
    expect(swatches.any((s) => s['id'] == 'sky'), isTrue);

    final taskJson = (doc['tasks'] as List).single as Map<String, dynamic>;
    expect(taskJson['auto_swatch_id'], 'sky');
    expect(taskJson['override_swatch_id'], 'custom1');
    expect(taskJson.containsKey('auto_hue'), isFalse);

    final tagJson = (doc['tags'] as List).single as Map<String, dynamic>;
    expect(tagJson['swatch_id'], 'leaf');
    expect(tagJson.containsKey('hue'), isFalse);

    // Wipe into a fresh DB.
    await repo.delete('t1');
    await repo.deleteTag('tg1');
    await db.delete('color_swatch', where: 'id = ?', whereArgs: ['custom1']);
    await settings.write(const AppSettings());

    final result = await backup.importJson(json);
    expect(result.importedTasks, 1);
    expect(result.importedTags, 1);
    expect(result.skippedDuplicates, 0);

    final swatchList = await repo.listSwatches();
    expect(swatchList.any((s) => s.id == 'custom1'), isTrue);

    final task = await repo.getById('t1');
    expect(task, isNotNull);
    expect(task!.title, 'clip');
    expect(task.autoSwatchId, 'sky');
    expect(task.overrideSwatchId, 'custom1');
    expect(await repo.tagIdsForTask('t1'), ['tg1']);

    final tag = (await repo.listTags()).singleWhere((t) => t.id == 'tg1');
    expect(tag.swatchId, 'leaf');

    final s = await settings.read();
    expect(s.visibleStartHour, 7);
    expect(s.urgencyWindowDays, 5);
  });

  test('import v1 JSON maps hues to swatches and rebinds ids', () async {
    const v1 = '''
{
  "version": 1,
  "exportedAt": 1,
  "tasks": [{
    "id": "t-v1",
    "title": "legacy",
    "planned_start": 100,
    "planned_end": 200,
    "auto_hue": 218,
    "override_hue": 150,
    "created_at": 1,
    "is_done": false,
    "tag_ids": ["tg-v1"]
  }],
  "tags": [{
    "id": "tg-v1",
    "name": "old-tag",
    "hue": 150
  }],
  "settings": {
    "visible_start_hour": 8,
    "visible_end_hour": 22,
    "urgency_window_days": 7
  }
}
''';

    final result = await backup.importJson(v1);
    expect(result.importedTasks, 1);
    expect(result.importedTags, 1);

    final task = await repo.getById('t-v1');
    expect(task, isNotNull);
    expect(task!.autoSwatchId, 'azure');

    final swatches = await repo.listSwatches();
    final custom = swatches.where((s) => s.hue == 150).toList();
    expect(custom, hasLength(1));
    expect(custom.single.name, '自定义色');

    expect(task.overrideSwatchId, custom.single.id);

    final tag = (await repo.listTags()).singleWhere((t) => t.id == 'tg-v1');
    expect(tag.swatchId, custom.single.id);
  });

  test('duplicate task ids are skipped and counted', () async {
    await seed();
    final json = await backup.exportJson();
    final result = await backup.importJson(json);
    expect(result.importedTasks, 0);
    expect(result.skippedDuplicates, 1);
  });

  test('invalid backup is rejected without applying anything', () async {
    await seed();
    expect(
      () => backup.importJson('{"version":2,"tasks":[{"id":"x"}],"tags":[],"settings":{}}'),
      throwsA(isA<BackupValidationException>()),
    );
    // Original data still present.
    expect(await repo.getById('t1'), isNotNull);
  });

  test('end before start fails validation', () async {
    const bad = '''
{
  "version": 2,
  "exportedAt": 1,
  "color_swatches": [],
  "tasks": [{
    "id": "bad",
    "title": "x",
    "planned_start": 200,
    "planned_end": 100,
    "auto_swatch_id": "azure",
    "created_at": 1,
    "is_done": false
  }],
  "tags": [],
  "settings": {
    "visible_start_hour": 8,
    "visible_end_hour": 22,
    "urgency_window_days": 7
  }
}
''';
    expect(
      () => backup.importJson(bad),
      throwsA(isA<BackupValidationException>()),
    );
  });
}
