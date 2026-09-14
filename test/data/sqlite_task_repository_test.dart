import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_task_repository.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/models/default_color.dart';
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
    await db.insert('default_color', {
      'id': 'def-azure',
      'argb': kFallbackArgb,
      'is_current': 1,
      'sort_order': 0,
    });
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

  test('task ending exactly at midnight is not returned on next day', () async {
    final t = Task(
      id: 'exact',
      title: 'ends at midnight',
      plannedStart: WallClock.minutes(DateTime(2026, 8, 8, 22, 0)),
      plannedEnd: WallClock.minutes(DateTime(2026, 8, 9, 0, 0)),
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

  test('upsert round-trips tagId and overrideArgb', () async {
    await repo.upsertTag(
      const Tag(id: 'tg1', name: '学习', argb: 0xFF7EB6F0, sortOrder: 0),
    );
    final t = Task(
      id: 'p',
      title: 'tagged',
      plannedStart: 100,
      plannedEnd: 200,
      tagId: 'tg1',
      overrideArgb: 0xFF60A5FA,
      createdAt: 0,
    );
    await repo.upsert(t);
    final got = (await repo.getById(t.id))!;
    expect(got.tagId, 'tg1');
    expect(got.overrideArgb, 0xFF60A5FA);
  });

  test('upsertTag then listTags returns name and argb', () async {
    await repo.upsertTag(
      const Tag(id: 'tg1', name: '学习', argb: 0xFF7EB6F0, sortOrder: 1),
    );
    await repo.upsertTag(
      const Tag(id: 'tg2', name: '跳舞', argb: 0xFF93C5FD, sortOrder: 0),
    );
    final tags = await repo.listTags();
    expect(tags, hasLength(2));
    final byName = {for (final t in tags) t.name: t};
    expect(byName['学习']!.argb, 0xFF7EB6F0);
    expect(byName['跳舞']!.argb, 0xFF93C5FD);
  });

  test('listTags orders by sort_order ASC', () async {
    await repo.upsertTag(
      const Tag(id: 'z', name: 'zeta', argb: 0xFF111111, sortOrder: 0),
    );
    await repo.upsertTag(
      const Tag(id: 'a', name: 'alpha', argb: 0xFF222222, sortOrder: 1),
    );
    final names = (await repo.listTags()).map((t) => t.name);
    expect(names, ['zeta', 'alpha']);
  });

  test('upsertTag rejects duplicate names', () async {
    await repo.upsertTag(
      const Tag(id: 'a', name: '学习', argb: 0xFF7EB6F0, sortOrder: 0),
    );
    expect(
      () => repo.upsertTag(
        const Tag(id: 'b', name: '学习', argb: 0xFF60A5FA, sortOrder: 1),
      ),
      throwsA(isA<TagOperationException>()),
    );
  });

  test('deleteTag nulls task.tag_id and allows deleting the last tag', () async {
    await repo.upsertTag(
      const Tag(id: 'tg1', name: '学习', argb: 0xFF7EB6F0, sortOrder: 0),
    );
    await repo.upsert(Task(
      id: 'p',
      title: 'tagged',
      plannedStart: 100,
      plannedEnd: 200,
      tagId: 'tg1',
      createdAt: 0,
    ));
    await repo.deleteTag('tg1');
    expect(await repo.listTags(), isEmpty);
    expect((await repo.getById('p'))!.tagId, isNull);
  });

  test('upsertDefaultColor new row becomes current', () async {
    await repo.upsertDefaultColor(
      const DefaultColor(
        id: 'd2',
        argb: 0xFFFFDAC1,
        sortOrder: 1,
        isCurrent: false,
      ),
    );
    final all = await repo.listDefaultColors();
    expect(all.where((c) => c.isCurrent).map((c) => c.id), ['d2']);
    expect((await repo.currentDefaultColor())!.id, 'd2');
  });

  test('recolor of non-current default color does not steal current', () async {
    await repo.upsertDefaultColor(
      const DefaultColor(
        id: 'd2',
        argb: 0xFFFFDAC1,
        sortOrder: 1,
        isCurrent: false,
      ),
    );
    expect((await repo.currentDefaultColor())!.id, 'd2');
    await repo.upsertDefaultColor(
      const DefaultColor(
        id: 'def-azure',
        argb: 0xFF112233,
        sortOrder: 0,
        isCurrent: false,
      ),
    );
    expect((await repo.currentDefaultColor())!.id, 'd2');
    final azure = (await repo.listDefaultColors())
        .firstWhere((c) => c.id == 'def-azure');
    expect(azure.argb, 0xFF112233);
    expect(azure.isCurrent, isFalse);
  });

  test('deleteDefaultColor of current promotes first remaining', () async {
    await repo.upsertDefaultColor(
      const DefaultColor(
        id: 'd2',
        argb: 0xFFFFDAC1,
        sortOrder: 1,
        isCurrent: false,
      ),
    );
    expect((await repo.currentDefaultColor())!.id, 'd2');
    await repo.deleteDefaultColor('d2');
    final current = await repo.currentDefaultColor();
    expect(current!.id, 'def-azure');
    expect(current.isCurrent, isTrue);
  });

  test('deleteDefaultColor last row leaves current null', () async {
    await repo.deleteDefaultColor('def-azure');
    expect(await repo.listDefaultColors(), isEmpty);
    expect(await repo.currentDefaultColor(), isNull);
  });

  test('watchDefaultColors emits after mutation', () async {
    final stream = repo.watchDefaultColors();
    final emissions = <List<DefaultColor>>[];
    final sub = stream.listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await repo.upsertDefaultColor(
      const DefaultColor(
        id: 'd2',
        argb: 0xFFFFDAC1,
        sortOrder: 1,
        isCurrent: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.length, 2);
    expect(emissions.last.where((c) => c.isCurrent).map((c) => c.id), ['d2']);
  });
}
