import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
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

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.applySchema(db);
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
        autoHue: 200,
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
      autoHue: 10,
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
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', hue: 120));
    await repo.upsertTag(const Tag(id: 'tg2', name: 'shoot', hue: 30));
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
      autoHue: 42,
      createdAt: 0,
    );
    await repo.upsert(t);
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', hue: 120));
    await repo.setTaskTags(t.id, ['tg1']);
    await repo.deleteTag('tg1');
    expect(await repo.listTags(), isEmpty);
    expect(await repo.tagIdsForTask(t.id), isEmpty);
    expect((await repo.getById(t.id))!.primaryTagId, isNull);
  });

  test('delete removes task and its tag links', () async {
    final t = overnightTask();
    await repo.upsert(t);
    await repo.upsertTag(const Tag(id: 'tg1', name: 'edit', hue: 120));
    await repo.setTaskTags(t.id, ['tg1']);
    await repo.delete(t.id);
    expect(await repo.getById(t.id), isNull);
    expect(await repo.tagIdsForTask(t.id), isEmpty);
  });
}
