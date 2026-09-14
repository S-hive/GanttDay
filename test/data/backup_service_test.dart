import 'dart:convert';

import 'package:ganttday/data/backup/backup_service.dart';
import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_settings_store.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/models/app_settings.dart';
import 'package:ganttday/domain/models/default_color.dart';
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
    await db.insert('default_color', {
      'id': 'def-azure',
      'argb': kFallbackArgb,
      'is_current': 1,
      'sort_order': 0,
    });
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
    await repo.upsertTag(
      const Tag(id: 'tg1', name: 'edit', argb: 0xFFE2F0CB, sortOrder: 0),
    );
    await repo.upsert(Task(
      id: 't1',
      title: 'clip',
      plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 9)),
      plannedEnd: WallClock.minutes(DateTime(2026, 8, 8, 11)),
      tagId: 'tg1',
      overrideArgb: 0xFFAA5533,
      createdAt: 1,
    ));
    await settings.write(const AppSettings(
      visibleStartHour: 7,
      visibleEndHour: 21,
      urgencyWindowDays: 5,
    ));
  }

  test('export writes version 3 keys for tag default color and override',
      () async {
    await seed();
    final json = await backup.exportJson();
    final doc = jsonDecode(json) as Map<String, dynamic>;

    expect(doc['version'], 3);
    expect(doc.containsKey('color_swatches'), isFalse);

    final tags = doc['tags'] as List;
    expect(tags, hasLength(1));
    expect(tags.single, containsPair('id', 'tg1'));
    expect(tags.single, containsPair('name', 'edit'));
    expect(tags.single, containsPair('argb', 0xFFE2F0CB));
    expect(tags.single, containsPair('sort_order', 0));
    expect(tags.single.containsKey('swatch_id'), isFalse);

    final defaults = doc['default_colors'] as List;
    expect(defaults, isNotEmpty);
    expect(defaults.first, contains('id'));
    expect(defaults.first, contains('argb'));
    expect(defaults.first, contains('is_current'));
    expect(defaults.first, contains('sort_order'));

    final taskJson = (doc['tasks'] as List).single as Map<String, dynamic>;
    expect(taskJson['tag_id'], 'tg1');
    expect(taskJson['override_argb'], 0xFFAA5533);
    expect(taskJson.containsKey('auto_swatch_id'), isFalse);
    expect(taskJson.containsKey('override_swatch_id'), isFalse);
    expect(taskJson.containsKey('primary_tag_id'), isFalse);
    expect(taskJson.containsKey('tag_ids'), isFalse);
  });

  test('import v3 round-trip restores tags default colors and tasks', () async {
    await seed();
    final json = await backup.exportJson();

    await repo.delete('t1');
    await repo.deleteTag('tg1');
    await repo.deleteDefaultColor('def-azure');
    await settings.write(const AppSettings());

    final result = await backup.importJson(json);
    expect(result.importedTasks, 1);
    expect(result.importedTags, 1);
    expect(result.skippedDuplicates, 0);

    final task = await repo.getById('t1');
    expect(task, isNotNull);
    expect(task!.title, 'clip');
    expect(task.tagId, 'tg1');
    expect(task.overrideArgb, 0xFFAA5533);

    final tag = (await repo.listTags()).singleWhere((t) => t.id == 'tg1');
    expect(tag.argb, 0xFFE2F0CB);

    final current = await repo.currentDefaultColor();
    expect(current, isNotNull);
    expect(current!.argb, kFallbackArgb);

    final s = await settings.read();
    expect(s.visibleStartHour, 7);
    expect(s.urgencyWindowDays, 5);
  });

  test(
      'import v3 onto seeded db replaces default_color; leftover seed is gone',
      () async {
    expect((await repo.listDefaultColors()).map((c) => c.id), ['def-azure']);

    const imported = DefaultColor(
      id: 'imported-peach',
      argb: 0xFFFFDAC1,
      sortOrder: 0,
      isCurrent: true,
    );
    final json = jsonEncode({
      'version': 3,
      'exportedAt': 1,
      'default_colors': [
        {
          'id': imported.id,
          'argb': imported.argb,
          'is_current': 1,
          'sort_order': imported.sortOrder,
        },
      ],
      'tasks': [],
      'tags': [],
      'settings': {
        'visible_start_hour': 8,
        'visible_end_hour': 22,
        'urgency_window_days': 7,
      },
    });

    await backup.importJson(json);

    final colors = await repo.listDefaultColors();
    expect(colors, hasLength(1));
    expect(colors.single.id, imported.id);
    expect(colors.single.argb, imported.argb);
    expect(colors.single.isCurrent, imported.isCurrent);
    expect(colors.single.sortOrder, imported.sortOrder);
    expect(colors.any((c) => c.id == 'def-azure'), isFalse);
  });

  test(
      'import v2 onto seeded schema 3 keeps one current from is_default, no extra seed',
      () async {
    expect((await repo.listDefaultColors()).map((c) => c.id), ['def-azure']);

    final v2 = jsonEncode({
      'version': 2,
      'exportedAt': 1,
      'color_swatches': [
        {
          'id': 'leaf',
          'name': '芽绿',
          'argb': 0xFFE2F0CB,
          'hue': 83,
          'saturation': 0.551,
          'lightness': 0.869,
          'is_default': 0,
          'sort_order': 2,
          'slate': 0,
        },
        {
          'id': 'azure',
          'name': '霁蓝',
          'argb': kFallbackArgb,
          'hue': 218,
          'saturation': 0.661,
          'lightness': 0.561,
          'is_default': 1,
          'sort_order': 0,
          'slate': 0,
        },
      ],
      'tasks': [],
      'tags': [],
      'settings': {
        'visible_start_hour': 8,
        'visible_end_hour': 22,
        'urgency_window_days': 7,
      },
    });

    await backup.importJson(v2);

    final colors = await repo.listDefaultColors();
    expect(colors, hasLength(1));
    expect(colors.single.isCurrent, isTrue);
    expect(colors.single.argb, kFallbackArgb);
    expect(colors.single.id, isNot('def-azure'));
  });

  test('import v2 shared swatch copies ARGB onto independent tags', () async {
    final v2 = jsonEncode({
      'version': 2,
      'exportedAt': 1,
      'color_swatches': [
        {
          'id': 'leaf',
          'name': '芽绿',
          'argb': 0xFFE2F0CB,
          'hue': 83,
          'saturation': 0.551,
          'lightness': 0.869,
          'is_default': 0,
          'sort_order': 2,
          'slate': 0,
        },
        {
          'id': 'azure',
          'name': '霁蓝',
          'argb': kFallbackArgb,
          'hue': 218,
          'saturation': 0.661,
          'lightness': 0.561,
          'is_default': 1,
          'sort_order': 0,
          'slate': 0,
        },
      ],
      'tasks': [
        {
          'id': 't-v2',
          'title': 'shared',
          'planned_start': 100,
          'planned_end': 200,
          'auto_swatch_id': 'azure',
          'override_swatch_id': 'leaf',
          'primary_tag_id': 'tg-a',
          'tag_ids': ['tg-a', 'tg-b'],
          'created_at': 1,
          'is_done': false,
        }
      ],
      'tags': [
        {'id': 'tg-a', 'name': '学习', 'swatch_id': 'leaf'},
        {'id': 'tg-b', 'name': '跳舞', 'swatch_id': 'leaf'},
      ],
      'settings': {
        'visible_start_hour': 8,
        'visible_end_hour': 22,
        'urgency_window_days': 7,
      },
    });

    final result = await backup.importJson(v2);
    expect(result.importedTasks, 1);
    expect(result.importedTags, 2);

    final tags = await repo.listTags();
    expect(tags, hasLength(2));
    expect({for (final t in tags) t.id}, {'tg-a', 'tg-b'});
    expect(tags.map((t) => t.argb).toSet(), {0xFFE2F0CB});

    final task = await repo.getById('t-v2');
    expect(task!.tagId, 'tg-a');
    expect(task.overrideArgb, 0xFFE2F0CB);

    final current = await repo.currentDefaultColor();
    expect(current!.argb, kFallbackArgb);
  });

  test('import v1 JSON copies hue-resolved ARGB onto tags and override',
      () async {
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
    "primary_tag_id": "tg-v1",
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
    expect(task!.tagId, 'tg-v1');
    expect(task.overrideArgb, isNotNull);

    final tag = (await repo.listTags()).singleWhere((t) => t.id == 'tg-v1');
    expect(tag.argb, task.overrideArgb);
    expect(tag.argb, isNot(kFallbackArgb));
  });

  test('malformed v1 backup is rejected without applying anything', () async {
    await seed();
    const badV1 = '''
{
  "version": 1,
  "exportedAt": 1,
  "tasks": [{
    "id": "t-bad",
    "title": "x",
    "planned_start": 200,
    "planned_end": 100,
    "auto_hue": 218,
    "created_at": 1,
    "is_done": false
  }],
  "tags": [{
    "id": "tg-ok",
    "name": "ok",
    "hue": 150
  }],
  "settings": {
    "visible_start_hour": 8,
    "visible_end_hour": 22,
    "urgency_window_days": 7
  }
}
''';

    expect(
      () => backup.importJson(badV1),
      throwsA(isA<BackupValidationException>()),
    );

    expect(await repo.getById('t-bad'), isNull);
    expect((await repo.listTags()).any((t) => t.id == 'tg-ok'), isFalse);
    expect(await repo.getById('t1'), isNotNull);
    final s = await settings.read();
    expect(s.visibleStartHour, 7);
    expect(s.urgencyWindowDays, 5);
  });

  test('malformed v1 backup on empty db leaves no imports', () async {
    await repo.deleteDefaultColor('def-azure');
    const badV1 = '''
{
  "version": 1,
  "exportedAt": 1,
  "tasks": [{"id": "x"}],
  "tags": [],
  "settings": {
    "visible_start_hour": 8,
    "visible_end_hour": 22,
    "urgency_window_days": 7
  }
}
''';

    expect(
      () => backup.importJson(badV1),
      throwsA(isA<BackupValidationException>()),
    );

    expect(await repo.listTags(), isEmpty);
    expect(await db.query('task'), isEmpty);
    final s = await settings.read();
    expect(s.visibleStartHour, AppSettings().visibleStartHour);
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
      () => backup.importJson(
          '{"version":3,"tasks":[{"id":"x"}],"tags":[],"default_colors":[],"settings":{}}'),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await repo.getById('t1'), isNotNull);
  });

  test('end before start fails validation', () async {
    const bad = '''
{
  "version": 3,
  "exportedAt": 1,
  "default_colors": [],
  "tasks": [{
    "id": "bad",
    "title": "x",
    "planned_start": 200,
    "planned_end": 100,
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
