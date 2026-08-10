import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
import 'package:ganttday/data/sqlite/swatch_migration.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/models/color_swatch.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/platform/task_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SqliteTaskRepository repo;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.applySchema(db);
    await seedFactorySwatches(db);
    repo = SqliteTaskRepository(db);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  Task overnightTask() => Task(
        id: 'night',
        title: 'render video overnight',
        plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 23, 0)),
        plannedEnd: WallClock.minutes(DateTime(2026, 8, 9, 1, 0)),
        autoSwatchId: 'sky',
        createdAt: 0,
      );

  test('watchTasksOverlapping returns overnight task on both days', () async {
    await repo.upsert(overnightTask());
    final day1 = WallClock.minutes(DateTime(2026, 8, 8));
    final day2 = WallClock.minutes(DateTime(2026, 8, 9));
    final onDay1 = await repo.watchTasksOverlapping(day1, day1 + 1440).first;
    final onDay2 = await repo.watchTasksOverlapping(day2, day2 + 1440).first;
    expect(onDay1, hasLength(1));
    expect(onDay2, hasLength(1));
  });

  test('task ending exactly at midnight is not returned on next day',
      () async {
    final t = Task(
      id: 'exact',
      title: 'ends at midnight',
      plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 22, 0)),
      plannedEnd: WallClock.minutes(DateTime(2026, 8, 9, 0, 0)),
      autoSwatchId: 'peach',
      createdAt: 0,
    );
    await repo.upsert(t);
    final day2 = WallClock.minutes(DateTime(2026, 8, 9));
    final onDay2 = await repo.watchTasksOverlapping(day2, day2 + 1440).first;
    expect(onDay2, isEmpty);
  });

  test('watch emits again after a mutation', () async {
    final day1 = WallClock.minutes(DateTime(2026, 8, 8));
    final stream = repo.watchTasksOverlapping(day1, day1 + 1440);
    final emissions = <List<Task>>[];
    final sub = stream.listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.upsert(overnightTask());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.length, 2);
    expect(emissions.first, isEmpty);
    expect(emissions.last, hasLength(1));
  });

  test('complete sets actuals and is_done', () async {
    final t = overnightTask();
    await repo.upsert(t);
    await repo.complete(t.id,
        actualStart: t.plannedStart - 30, actualEnd: t.plannedEnd + 45);
    final got = (await repo.getById(t.id))!;
    expect(got.isDone, true);
    expect(got.actualStart, t.plannedStart - 30);
    expect(got.actualEnd, t.plannedEnd + 45);
  });

  test('uncomplete clears actuals completely', () async {
    final t = overnightTask();
    await repo.upsert(t);
    await repo.complete(t.id,
        actualStart: t.plannedStart, actualEnd: t.plannedEnd);
    await repo.uncomplete(t.id);
    final got = (await repo.getById(t.id))!;
    expect(got.isDone, false);
    expect(got.actualStart, isNull);
    expect(got.actualEnd, isNull);
  });

  test('tag CRUD and task-tag assignment', () async {
    final t = overnightTask();
    await repo.upsert(t);
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', swatchId: 'leaf'));
    await repo.upsertTag(const Tag(id: 'tg2', name: 'shoot', swatchId: 'peach'));
    await repo.setTaskTags(t.id, ['tg1', 'tg2']);
    expect(await repo.tagIdsForTask(t.id), unorderedEquals(['tg1', 'tg2']));

    await repo.setTaskTags(t.id, ['tg2']);
    expect(await repo.tagIdsForTask(t.id), ['tg2']);

    expect((await repo.listTags()).map((x) => x.name), ['edit', 'shoot']);
  });

  test('deleteTag clears links and primary references', () async {
    final t = Task(
      id: 'p',
      title: 'primary tagged',
      plannedStart: 100,
      plannedEnd: 200,
      primaryTagId: 'tg1',
      autoSwatchId: 'azure',
      createdAt: 0,
    );
    await repo.upsert(t);
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', swatchId: 'leaf'));
    await repo.setTaskTags(t.id, ['tg1']);
    await repo.deleteTag('tg1');
    expect(await repo.listTags(), isEmpty);
    expect(await repo.tagIdsForTask(t.id), isEmpty);
    expect((await repo.getById(t.id))!.primaryTagId, isNull);
  });

  test('delete removes task and its tag links', () async {
    final t = overnightTask();
    await repo.upsert(t);
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', swatchId: 'leaf'));
    await repo.setTaskTags(t.id, ['tg1']);
    await repo.delete(t.id);
    expect(await repo.getById(t.id), isNull);
    expect(await repo.tagIdsForTask(t.id), isEmpty);
  });

  group('swatch CRUD', () {
    test('listSwatches returns factory seeds ordered by sort_order', () async {
      final swatches = await repo.listSwatches();
      expect(swatches, hasLength(kFactoryColorSwatches.length));
      expect(swatches.map((s) => s.id).toList(),
          kFactoryColorSwatches.map((s) => s.id).toList());
    });

    test('defaultSwatch returns the seeded default', () async {
      final d = await repo.defaultSwatch();
      expect(d.id, 'azure');
      expect(d.isDefault, isTrue);
    });

    test('upsertSwatch inserts and updates', () async {
      const custom = ColorSwatch(
        id: 'custom1',
        name: 'My red',
        argb: 0xFFFF0000,
        hue: 0,
        saturation: 1.0,
        lightness: 0.5,
        sortOrder: 99,
      );
      await repo.upsertSwatch(custom);
      expect(await repo.listSwatches(), contains(predicate<ColorSwatch>(
          (s) => s.id == 'custom1' && s.name == 'My red')));

      await repo.upsertSwatch(custom.copyWith(name: 'Renamed'));
      final got =
          (await repo.listSwatches()).singleWhere((s) => s.id == 'custom1');
      expect(got.name, 'Renamed');
    });

    test('upsertSwatch with isDefault clears previous default', () async {
      await repo.upsertSwatch(
        kFactoryColorSwatches.firstWhere((s) => s.id == 'mint').copyWith(
          isDefault: true,
        ),
      );
      final all = await repo.listSwatches();
      expect(all.where((s) => s.isDefault).map((s) => s.id), ['mint']);
    });

    test('setDefaultSwatch clears previous default', () async {
      await repo.setDefaultSwatch('mint');
      final all = await repo.listSwatches();
      expect(all.where((s) => s.isDefault).map((s) => s.id), ['mint']);
    });

    test('deleteSwatch rebinds tasks and tags', () async {
      const taskId = 'swatch-task';
      await repo.upsertTag(const Tag(id: 'tg', name: 'a', swatchId: 'peach'));
      await repo.upsert(Task(
        id: taskId,
        title: 'colored',
        plannedStart: 100,
        plannedEnd: 200,
        autoSwatchId: 'peach',
        overrideSwatchId: 'peach',
        createdAt: 0,
      ));
      await repo.deleteSwatch('peach', rebindToId: 'azure');
      expect((await repo.listTags()).single.swatchId, 'azure');
      final task = (await repo.getById(taskId))!;
      expect(task.autoSwatchId, 'azure');
      expect(task.overrideSwatchId, 'azure');
      expect(
        await repo.listSwatches(),
        isNot(contains(predicate<ColorSwatch>((s) => s.id == 'peach'))),
      );
    });

    test('deleteSwatch sets rebind target as default when deleting default',
        () async {
      await repo.deleteSwatch('azure', rebindToId: 'mint');
      final d = await repo.defaultSwatch();
      expect(d.id, 'mint');
    });

    test('cannot delete last swatch', () async {
      var swatches = await repo.listSwatches();
      while (swatches.length > 1) {
        final victim = swatches.firstWhere((s) => !s.isDefault);
        final rebind = swatches.firstWhere((s) => s.id != victim.id);
        await repo.deleteSwatch(victim.id, rebindToId: rebind.id);
        swatches = await repo.listSwatches();
      }
      expect(swatches, hasLength(1));
      expect(
        () => repo.deleteSwatch(swatches.single.id, rebindToId: 'azure'),
        throwsA(isA<SwatchOperationException>()),
      );
    });

    test('deleteSwatch rejects invalid rebind target', () async {
      expect(
        () => repo.deleteSwatch('peach', rebindToId: 'peach'),
        throwsA(isA<SwatchOperationException>()),
      );
      expect(
        () => repo.deleteSwatch('peach', rebindToId: 'missing'),
        throwsA(isA<SwatchOperationException>()),
      );
    });

    test('watchSwatches emits again after mutation', () async {
      final stream = repo.watchSwatches();
      final emissions = <List<ColorSwatch>>[];
      final sub = stream.listen(emissions.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await repo.setDefaultSwatch('mint');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      expect(emissions.length, 2);
      expect(
        emissions.last.where((s) => s.isDefault).map((s) => s.id),
        ['mint'],
      );
    });
  });
}
