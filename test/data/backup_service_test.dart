import 'package:ganttday/data/backup/backup_service.dart';
import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_settings_store.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
import 'package:ganttday/domain/models/app_settings.dart';
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
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', swatchId: 'leaf'));
    await repo.upsert(Task(
      id: 't1',
      title: 'clip',
      plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 9)),
      plannedEnd: WallClock.minutes(DateTime(2026, 8, 8, 11)),
      autoSwatchId: 'sky',
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

  test('round-trip export/import restores tasks tags and settings', () async {
    await seed();
    final json = await backup.exportJson();

    // Wipe into a fresh DB.
    await repo.delete('t1');
    await repo.deleteTag('tg1');
    await settings.write(const AppSettings());

    final result = await backup.importJson(json);
    expect(result.importedTasks, 1);
    expect(result.importedTags, 1);
    expect(result.skippedDuplicates, 0);

    final task = await repo.getById('t1');
    expect(task, isNotNull);
    expect(task!.title, 'clip');
    expect(await repo.tagIdsForTask('t1'), ['tg1']);
    final s = await settings.read();
    expect(s.visibleStartHour, 7);
    expect(s.urgencyWindowDays, 5);
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
      () => backup.importJson('{"version":1,"tasks":[{"id":"x"}],"tags":[],"settings":{}}'),
      throwsA(isA<BackupValidationException>()),
    );
    // Original data still present.
    expect(await repo.getById('t1'), isNotNull);
  });

  test('end before start fails validation', () async {
    final bad = '''
{
  "version": 1,
  "exportedAt": 1,
  "tasks": [{
    "id": "bad",
    "title": "x",
    "planned_start": 200,
    "planned_end": 100,
    "auto_hue": 1,
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
