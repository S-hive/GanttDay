import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/month/month_span_layout.dart';
import 'package:test/test.dart';

Task _task({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
}) {
  return Task(
    id: id,
    title: title,
    plannedStart: WallClock.minutes(start),
    plannedEnd: WallClock.minutes(end),
    autoHue: 210,
    createdAt: WallClock.minutes(start),
  );
}

void main() {
  final month = DateTime(2026, 8, 1);

  test('same-day-only task fills its day cell (window = itself)', () {
    final t = _task(
      id: 'a',
      title: '拍摄',
      start: DateTime(2026, 8, 5, 9),
      end: DateTime(2026, 8, 5, 12),
    );
    final weeks = buildMonthWeekLayouts(month: month, tasks: [t]);
    // 2026-08-05 is Wednesday → week Mon 8/3 … Sun 8/9 → day index 2
    final week = weeks.firstWhere(
        (w) => w.weekMonday == DateTime(2026, 8, 3));
    expect(week.bars, hasLength(1));
    final bar = week.bars.single;
    expect(bar.startFrac, closeTo(2.0, 1e-9));
    expect(bar.endFrac, closeTo(3.0, 1e-9));
    expect(bar.title, '拍摄');
  });

  test('same-day window is earliest–latest; bars map into it', () {
    final tasks = [
      _task(
        id: 'early',
        title: '早',
        start: DateTime(2026, 8, 5, 9),
        end: DateTime(2026, 8, 5, 10),
      ),
      _task(
        id: 'late',
        title: '晚',
        start: DateTime(2026, 8, 5, 16),
        end: DateTime(2026, 8, 5, 17),
      ),
    ];
    final weeks = buildMonthWeekLayouts(month: month, tasks: tasks);
    final week = weeks.firstWhere(
        (w) => w.weekMonday == DateTime(2026, 8, 3));
    // Window 09:00–17:00 (8h). Early 9–10 → 0–1/8; late 16–17 → 7/8–1.
    final early = week.bars.firstWhere((b) => b.taskId == 'early');
    final late = week.bars.firstWhere((b) => b.taskId == 'late');
    expect(early.startFrac, closeTo(2 + 0 / 8, 1e-9));
    expect(early.endFrac, closeTo(2 + 1 / 8, 1e-9));
    expect(late.startFrac, closeTo(2 + 7 / 8, 1e-9));
    expect(late.endFrac, closeTo(2 + 8 / 8, 1e-9));
  });

  test('cross-day task falls back to 0–24h when no same-day tasks', () {
    final t = _task(
      id: 'b',
      title: '跑步',
      start: DateTime(2026, 8, 3, 0),
      end: DateTime(2026, 8, 7, 0),
    );
    final weeks = buildMonthWeekLayouts(month: month, tasks: [t]);
    final week = weeks.firstWhere(
        (w) => w.weekMonday == DateTime(2026, 8, 3));
    expect(week.bars.single.startFrac, closeTo(0.0, 1e-9));
    expect(week.bars.single.endFrac, closeTo(4.0, 1e-9));
  });

  test('task crossing weeks is split into week segments', () {
    final t = _task(
      id: 'c',
      title: '跨周',
      start: DateTime(2026, 8, 7, 18),
      end: DateTime(2026, 8, 11, 10),
    );
    final weeks = buildMonthWeekLayouts(month: month, tasks: [t]);
    final w1 = weeks.firstWhere((w) => w.weekMonday == DateTime(2026, 8, 3));
    final w2 = weeks.firstWhere((w) => w.weekMonday == DateTime(2026, 8, 10));
    expect(w1.bars.single.startFrac, closeTo(4 + 18 / 24, 1e-9));
    expect(w1.bars.single.endFrac, closeTo(7.0, 1e-9));
    expect(w2.bars.single.startFrac, closeTo(0.0, 1e-9));
    expect(w2.bars.single.endFrac, closeTo(1 + 10 / 24, 1e-9));
  });

  test('keeps at most 10 tasks per day and reports overflow', () {
    final tasks = [
      for (var i = 0; i < 12; i++)
        _task(
          id: 't$i',
          title: 'T$i',
          start: DateTime(2026, 8, 10, i % 12),
          end: DateTime(2026, 8, 10, i % 12 + 1),
        ),
    ];
    final selected = selectVisibleMonthTasks(month: month, tasks: tasks);
    expect(selected.visible, hasLength(10));
    expect(selected.overflowByDay[10], 2);

    final weeks = buildMonthWeekLayouts(
      month: month,
      tasks: selected.visible,
      overflowByDay: selected.overflowByDay,
    );
    final week = weeks.firstWhere(
        (w) => w.weekMonday == DateTime(2026, 8, 10));
    expect(week.bars, hasLength(10));
    expect(week.overflowByDay[10], 2);
  });

  test('end exactly at midnight is exclusive (no next-day spill)', () {
    final t = _task(
      id: 'd',
      title: '到午夜',
      start: DateTime(2026, 8, 5, 22),
      end: DateTime(2026, 8, 6, 0),
    );
    // Same-day 22:00–24:00 → window = itself → fills the Wed cell.
    final weeks = buildMonthWeekLayouts(month: month, tasks: [t]);
    final week = weeks.firstWhere(
        (w) => w.weekMonday == DateTime(2026, 8, 3));
    expect(week.bars.single.startFrac, closeTo(2.0, 1e-9));
    expect(week.bars.single.endFrac, closeTo(3.0, 1e-9));
  });

  test('dayTimeWindowFor uses same-day earliest and latest only', () {
    final day0 = WallClock.minutes(DateTime(2026, 8, 5));
    final win = dayTimeWindowFor(
      day0: day0,
      tasks: [
        _task(
          id: 'a',
          title: 'a',
          start: DateTime(2026, 8, 5, 10),
          end: DateTime(2026, 8, 5, 11),
        ),
        _task(
          id: 'cross',
          title: 'cross',
          start: DateTime(2026, 8, 4, 20),
          end: DateTime(2026, 8, 6, 8),
        ),
        _task(
          id: 'b',
          title: 'b',
          start: DateTime(2026, 8, 5, 14),
          end: DateTime(2026, 8, 5, 16),
        ),
      ],
    );
    expect(win.start, WallClock.minutes(DateTime(2026, 8, 5, 10)));
    expect(win.end, WallClock.minutes(DateTime(2026, 8, 5, 16)));
  });
}
