import '../../domain/gantt/lane_layout.dart';
import '../../domain/models/gantt_segment.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';

const int kMonthMaxBarsPerDay = 10;

class MonthTaskSelection {
  const MonthTaskSelection({
    required this.visible,
    required this.overflowByDay,
  });

  final List<Task> visible;

  /// Day-of-month → count of tasks not shown that day.
  final Map<int, int> overflowByDay;
}

class MonthPlacedBar {
  const MonthPlacedBar({
    required this.taskId,
    required this.title,
    required this.lane,
    required this.startFrac,
    required this.endFrac,
    required this.openDay,
    required this.spanStart,
    required this.spanEnd,
  });

  final String taskId;
  final String title;
  final int lane;

  /// Position within the week in day units: Monday 00:00 = 0, Sunday 24:00 = 7.
  final double startFrac;
  final double endFrac;

  /// Day view to open when the bar is tapped.
  final DateTime openDay;

  /// Full planned span (for hover detail).
  final WallMinutes spanStart;
  final WallMinutes spanEnd;
}

class MonthWeekLayout {
  const MonthWeekLayout({
    required this.weekMonday,
    required this.days,
    required this.bars,
    required this.overflowByDay,
    required this.laneCount,
  });

  final DateTime weekMonday;

  /// Always 7 calendar days starting at [weekMonday].
  final List<DateTime> days;
  final List<MonthPlacedBar> bars;

  /// Day-of-month → overflow count (only days in the displayed month).
  final Map<int, int> overflowByDay;
  final int laneCount;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime _mondayOnOrBefore(DateTime day) {
  final d = _dateOnly(day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// Same calendar day (exclusive end at 00:00 counts as previous day).
bool isSameCalendarDaySpan(WallMinutes start, WallMinutes end) {
  if (end <= start) return false;
  return WallClock.dayStart(start) == WallClock.dayStart(end - 1);
}

/// Per-day time axis for month cells: earliest–latest among same-day tasks.
class DayTimeWindow {
  const DayTimeWindow({required this.start, required this.end});

  final WallMinutes start;
  final WallMinutes end;

  double frac(WallMinutes t) {
    final span = end - start;
    if (span <= 0) return 0;
    return ((t - start) / span).clamp(0.0, 1.0);
  }
}

/// Window for [day0] from non-cross-day tasks; else full 0:00–24:00.
DayTimeWindow dayTimeWindowFor({
  required WallMinutes day0,
  required List<Task> tasks,
}) {
  final day1 = day0 + WallClock.minutesPerDay;
  WallMinutes? lo;
  WallMinutes? hi;
  for (final t in tasks) {
    if (!isSameCalendarDaySpan(t.plannedStart, t.plannedEnd)) continue;
    if (t.plannedEnd <= day0 || t.plannedStart >= day1) continue;
    lo = lo == null
        ? t.plannedStart
        : (t.plannedStart < lo ? t.plannedStart : lo);
    hi = hi == null ? t.plannedEnd : (t.plannedEnd > hi ? t.plannedEnd : hi);
  }
  if (lo == null || hi == null) {
    return DayTimeWindow(start: day0, end: day1);
  }
  if (hi <= lo) {
    hi = lo + 60;
  }
  return DayTimeWindow(start: lo, end: hi);
}

/// Days of [month] that half-open [start, end) overlaps.
List<int> monthDaysOverlapped({
  required DateTime month,
  required WallMinutes start,
  required WallMinutes end,
}) {
  final monthStart = WallClock.minutes(DateTime(month.year, month.month, 1));
  final monthEnd = WallClock.minutes(DateTime(month.year, month.month + 1, 1));
  var day = WallClock.dayStart(start);
  if (day < monthStart) day = monthStart;
  final last = end < monthEnd ? end : monthEnd;
  final out = <int>[];
  while (day < last) {
    out.add(WallClock.dateTime(day).day);
    day += WallClock.minutesPerDay;
  }
  return out;
}

/// Prefer earlier start, then longer span.
int _taskPriorityCompare(Task a, Task b) {
  final c = a.plannedStart.compareTo(b.plannedStart);
  if (c != 0) return c;
  return b.plannedEnd.compareTo(a.plannedEnd);
}

MonthTaskSelection selectVisibleMonthTasks({
  required DateTime month,
  required List<Task> tasks,
  int maxPerDay = kMonthMaxBarsPerDay,
}) {
  final sorted = [...tasks]..sort(_taskPriorityCompare);
  final dayCounts = <int, int>{};
  final visible = <Task>[];
  final visibleIds = <String>{};

  for (final t in sorted) {
    if (t.plannedEnd <= t.plannedStart) continue;
    final days = monthDaysOverlapped(
      month: month,
      start: t.plannedStart,
      end: t.plannedEnd,
    );
    if (days.isEmpty) continue;
    final fits = days.every((d) => (dayCounts[d] ?? 0) < maxPerDay);
    if (!fits) continue;
    visible.add(t);
    visibleIds.add(t.id);
    for (final d in days) {
      dayCounts[d] = (dayCounts[d] ?? 0) + 1;
    }
  }

  final totalByDay = <int, int>{};
  for (final t in tasks) {
    if (t.plannedEnd <= t.plannedStart) continue;
    for (final d in monthDaysOverlapped(
      month: month,
      start: t.plannedStart,
      end: t.plannedEnd,
    )) {
      totalByDay[d] = (totalByDay[d] ?? 0) + 1;
    }
  }

  final overflow = <int, int>{};
  for (final e in totalByDay.entries) {
    final shown = dayCounts[e.key] ?? 0;
    final n = e.value - shown;
    if (n > 0) overflow[e.key] = n;
  }

  return MonthTaskSelection(visible: visible, overflowByDay: overflow);
}

List<MonthWeekLayout> buildMonthWeekLayouts({
  required DateTime month,
  required List<Task> tasks,
  Map<int, int> overflowByDay = const {},
}) {
  final monthStart = DateTime(month.year, month.month, 1);
  final monthEnd = DateTime(month.year, month.month + 1, 1);
  final firstMonday = _mondayOnOrBefore(monthStart);
  // Last day of month, then Monday on or before the Sunday of that week.
  final lastDay = monthEnd.subtract(const Duration(days: 1));
  final lastMonday = _mondayOnOrBefore(lastDay);

  final weeks = <MonthWeekLayout>[];
  for (var monday = firstMonday;
      !monday.isAfter(lastMonday);
      monday = monday.add(const Duration(days: 7))) {
    weeks.add(_layoutWeek(
      weekMonday: monday,
      month: month,
      tasks: tasks,
      overflowByDay: overflowByDay,
    ));
  }
  return weeks;
}

MonthWeekLayout _layoutWeek({
  required DateTime weekMonday,
  required DateTime month,
  required List<Task> tasks,
  required Map<int, int> overflowByDay,
}) {
  final weekStart = WallClock.minutes(weekMonday);
  final weekEnd = weekStart + 7 * WallClock.minutesPerDay;
  final days = [
    for (var i = 0; i < 7; i++) weekMonday.add(Duration(days: i)),
  ];

  final segs = <GanttSegment>[];
  final byKey = <String, Task>{};
  for (final t in tasks) {
    final start = t.plannedStart > weekStart ? t.plannedStart : weekStart;
    final end = t.plannedEnd < weekEnd ? t.plannedEnd : weekEnd;
    if (end <= start) continue;
    final seg = GanttSegment(taskId: t.id, start: start, end: end);
    segs.add(seg);
    byKey[LaneLayout.keyOf(seg)] = t;
  }

  final windows = [
    for (var d = 0; d < 7; d++)
      dayTimeWindowFor(
        day0: weekStart + d * WallClock.minutesPerDay,
        tasks: tasks,
      ),
  ];

  double weekFrac(WallMinutes t, {required bool asEnd}) {
    // Exclusive end exactly on a day boundary → end of previous day (frac 1).
    var dayIndex = (t - weekStart) ~/ WallClock.minutesPerDay;
    var minute = t;
    if (asEnd &&
        t > weekStart &&
        (t - weekStart) % WallClock.minutesPerDay == 0 &&
        dayIndex > 0) {
      dayIndex -= 1;
      minute = weekStart + (dayIndex + 1) * WallClock.minutesPerDay;
    }
    if (dayIndex < 0) return 0;
    if (dayIndex >= 7) return 7;
    return dayIndex + windows[dayIndex].frac(minute);
  }

  final lanes = LaneLayout.assign(segs);
  final bars = <MonthPlacedBar>[];
  for (final seg in segs) {
    final t = byKey[LaneLayout.keyOf(seg)]!;
    final startFrac = weekFrac(seg.start, asEnd: false);
    final endFrac = weekFrac(seg.end, asEnd: true);
    final open = WallClock.dateTime(WallClock.dayStart(seg.start));
    bars.add(MonthPlacedBar(
      taskId: t.id,
      title: t.title,
      lane: lanes[LaneLayout.keyOf(seg)]!,
      startFrac: startFrac,
      endFrac: endFrac < startFrac ? startFrac : endFrac,
      openDay: DateTime(open.year, open.month, open.day),
      spanStart: t.plannedStart,
      spanEnd: t.plannedEnd,
    ));
  }

  final weekOverflow = <int, int>{};
  for (final d in days) {
    if (d.year == month.year && d.month == month.month) {
      final n = overflowByDay[d.day];
      if (n != null && n > 0) weekOverflow[d.day] = n;
    }
  }

  return MonthWeekLayout(
    weekMonday: weekMonday,
    days: days,
    bars: bars,
    overflowByDay: weekOverflow,
    laneCount: LaneLayout.laneCount(lanes),
  );
}
