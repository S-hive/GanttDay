import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/week/week_column_layout.dart';
import 'package:test/test.dart';

Task _task({
  required String id,
  required DateTime start,
  required DateTime end,
  String title = 't',
}) {
  return Task(
    id: id,
    title: title,
    plannedStart: WallClock.minutes(start),
    plannedEnd: WallClock.minutes(end),
    createdAt: WallClock.minutes(start),
  );
}

void main() {
  final monday = DateTime(2026, 8, 3); // Mon

  test('places same-day task with vertical fractions', () {
    final slots = layoutWeekSlots(
      weekMonday: monday,
      tasks: [
        _task(
          id: 'a',
          title: '拍摄',
          start: DateTime(2026, 8, 5, 9, 30),
          end: DateTime(2026, 8, 5, 12),
        ),
      ],
    );
    expect(slots, hasLength(1));
    expect(slots.single.dayIndex, 2); // Wed
    expect(slots.single.topFrac, closeTo(9.5 / 24, 1e-9));
    expect(slots.single.heightFrac, closeTo(2.5 / 24, 1e-9));
    expect(slots.single.columnIndex, 0);
    expect(slots.single.columnCount, 1);
  });

  test('splits multi-day task across days', () {
    final slots = layoutWeekSlots(
      weekMonday: monday,
      tasks: [
        _task(
          id: 'b',
          start: DateTime(2026, 8, 4, 18),
          end: DateTime(2026, 8, 6, 10),
        ),
      ],
    );
    expect(slots.map((s) => s.dayIndex).toList(), [1, 2, 3]);
    expect(slots[0].topFrac, closeTo(18 / 24, 1e-9));
    expect(slots[0].heightFrac, closeTo(6 / 24, 1e-9));
    expect(slots[1].topFrac, 0);
    expect(slots[1].heightFrac, 1);
    expect(slots[2].topFrac, 0);
    expect(slots[2].heightFrac, closeTo(10 / 24, 1e-9));
  });

  test('overlapping tasks share side-by-side columns', () {
    final slots = layoutWeekSlots(
      weekMonday: monday,
      tasks: [
        _task(
          id: 'a',
          title: '拍摄',
          start: DateTime(2026, 8, 5, 9, 30),
          end: DateTime(2026, 8, 5, 12),
        ),
        _task(
          id: 'b',
          title: '面试',
          start: DateTime(2026, 8, 5, 10),
          end: DateTime(2026, 8, 5, 12),
        ),
        _task(
          id: 'c',
          title: '剪辑',
          start: DateTime(2026, 8, 5, 13, 15),
          end: DateTime(2026, 8, 5, 14, 30),
        ),
      ],
    );
    final wed = slots.where((s) => s.dayIndex == 2).toList();
    expect(wed, hasLength(3));
    final a = wed.firstWhere((s) => s.taskId == 'a');
    final b = wed.firstWhere((s) => s.taskId == 'b');
    final c = wed.firstWhere((s) => s.taskId == 'c');
    expect(a.columnCount, 2);
    expect(b.columnCount, 2);
    expect({a.columnIndex, b.columnIndex}, {0, 1});
    expect(c.columnCount, 1);
    expect(c.columnIndex, 0);
  });
}
