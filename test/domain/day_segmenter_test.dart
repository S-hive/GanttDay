import 'package:ganttday/domain/gantt/day_segmenter.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

Task _task({
  required DateTime start,
  required DateTime end,
  String id = 'a',
}) {
  return Task(
    id: id,
    title: 'task',
    plannedStart: WallClock.minutes(start),
    plannedEnd: WallClock.minutes(end),
    autoHue: 200,
    createdAt: 0,
  );
}

void main() {
  test('overnight task yields segment on start day ending at midnight', () {
    final task = _task(
      start: DateTime(2026, 8, 8, 23, 0),
      end: DateTime(2026, 8, 9, 1, 0),
    );
    final segs = DaySegmenter.segmentsForDay(
      task,
      WallClock.minutes(DateTime(2026, 8, 8, 12)),
    );
    expect(segs, hasLength(1));
    expect(segs.single.start, task.plannedStart);
    expect(segs.single.end, WallClock.minutes(DateTime(2026, 8, 9)));
  });

  test('overnight task yields morning segment on next day', () {
    final task = _task(
      start: DateTime(2026, 8, 8, 23, 0),
      end: DateTime(2026, 8, 9, 1, 0),
    );
    final segs = DaySegmenter.segmentsForDay(
      task,
      WallClock.minutes(DateTime(2026, 8, 9, 12)),
    );
    expect(segs, hasLength(1));
    expect(segs.single.start, WallClock.minutes(DateTime(2026, 8, 9)));
    expect(segs.single.end, task.plannedEnd);
  });

  test('task ending exactly at midnight has no segment on next day', () {
    final task = _task(
      id: 'b',
      start: DateTime(2026, 8, 8, 22, 0),
      end: DateTime(2026, 8, 9, 0, 0),
    );
    final segs = DaySegmenter.segmentsForDay(
      task,
      WallClock.minutes(DateTime(2026, 8, 9, 12)),
    );
    expect(segs, isEmpty);
  });

  test('task fully inside a day is returned unclipped', () {
    final task = _task(
      start: DateTime(2026, 8, 8, 9, 0),
      end: DateTime(2026, 8, 8, 11, 0),
    );
    final segs = DaySegmenter.segmentsForDay(
      task,
      WallClock.minutes(DateTime(2026, 8, 8)),
    );
    expect(segs.single.start, task.plannedStart);
    expect(segs.single.end, task.plannedEnd);
  });

  test('task on another day yields nothing', () {
    final task = _task(
      start: DateTime(2026, 8, 8, 9, 0),
      end: DateTime(2026, 8, 8, 11, 0),
    );
    final segs = DaySegmenter.segmentsForDay(
      task,
      WallClock.minutes(DateTime(2026, 8, 10)),
    );
    expect(segs, isEmpty);
  });

  test('clipToRange keeps overnight span as one continuous segment', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 22, 0));
    final end = WallClock.minutes(DateTime(2026, 8, 9, 4, 30));
    final weekStart = WallClock.minutes(DateTime(2026, 8, 8));
    final weekEnd = weekStart + WallClock.minutesPerDay * 7;
    final segs = DaySegmenter.clipToRange(
      taskId: 'a',
      start: start,
      end: end,
      rangeStart: weekStart,
      rangeEnd: weekEnd,
    );
    expect(segs, hasLength(1));
    expect(segs.single.start, start);
    expect(segs.single.end, end);
  });
}
