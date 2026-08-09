import '../../domain/gantt/day_segmenter.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';

/// One day-clipped segment placed in the week grid (day column × time).
class WeekSlot {
  const WeekSlot({
    required this.taskId,
    required this.title,
    required this.dayIndex,
    required this.segStart,
    required this.segEnd,
    required this.spanStart,
    required this.spanEnd,
    required this.topFrac,
    required this.heightFrac,
    required this.columnIndex,
    required this.columnCount,
  });

  final String taskId;
  final String title;
  final int dayIndex;
  final WallMinutes segStart;
  final WallMinutes segEnd;
  final WallMinutes spanStart;
  final WallMinutes spanEnd;

  /// Vertical position within the day column, 0 = midnight, 1 = next midnight.
  final double topFrac;
  final double heightFrac;
  final int columnIndex;
  final int columnCount;
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Monday-based week slots for [tasks] overlapping the week.
List<WeekSlot> layoutWeekSlots({
  required DateTime weekMonday,
  required List<Task> tasks,
}) {
  final monday = _dateOnly(weekMonday);
  final weekStart = WallClock.minutes(monday);
  final weekEnd = weekStart + 7 * WallClock.minutesPerDay;

  final byDay = List.generate(7, (_) => <_RawSlot>[]);

  for (final task in tasks) {
    if (task.plannedEnd <= task.plannedStart) continue;
    for (var d = 0; d < 7; d++) {
      final day0 = weekStart + d * WallClock.minutesPerDay;
      final segs = DaySegmenter.clipToDay(
        taskId: task.id,
        start: task.plannedStart,
        end: task.plannedEnd,
        dayAny: day0,
      );
      if (segs.isEmpty) continue;
      // Also skip if day is outside week (shouldn't happen).
      if (day0 < weekStart || day0 >= weekEnd) continue;
      final seg = segs.single;
      final top = (seg.start - day0) / WallClock.minutesPerDay;
      final height = (seg.end - seg.start) / WallClock.minutesPerDay;
      byDay[d].add(_RawSlot(
        taskId: task.id,
        title: task.title,
        dayIndex: d,
        segStart: seg.start,
        segEnd: seg.end,
        spanStart: task.plannedStart,
        spanEnd: task.plannedEnd,
        topFrac: top,
        heightFrac: height,
      ));
    }
  }

  final out = <WeekSlot>[];
  for (final daySlots in byDay) {
    out.addAll(_packDay(daySlots));
  }
  return out;
}

class _RawSlot {
  _RawSlot({
    required this.taskId,
    required this.title,
    required this.dayIndex,
    required this.segStart,
    required this.segEnd,
    required this.spanStart,
    required this.spanEnd,
    required this.topFrac,
    required this.heightFrac,
  });

  final String taskId;
  final String title;
  final int dayIndex;
  final WallMinutes segStart;
  final WallMinutes segEnd;
  final WallMinutes spanStart;
  final WallMinutes spanEnd;
  final double topFrac;
  final double heightFrac;
  int columnIndex = 0;
  int columnCount = 1;
}

List<WeekSlot> _packDay(List<_RawSlot> items) {
  if (items.isEmpty) return const [];
  final sorted = [...items]..sort((a, b) {
      final c = a.segStart.compareTo(b.segStart);
      return c != 0 ? c : a.segEnd.compareTo(b.segEnd);
    });

  final colEnds = <int>[];
  for (final item in sorted) {
    var col = 0;
    while (col < colEnds.length && colEnds[col] > item.segStart) {
      col++;
    }
    if (col == colEnds.length) {
      colEnds.add(item.segEnd);
    } else {
      colEnds[col] = item.segEnd;
    }
    item.columnIndex = col;
  }

  // Connected components by time overlap → shared columnCount.
  final n = sorted.length;
  final parent = List<int>.generate(n, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a);
    final rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  bool overlaps(_RawSlot a, _RawSlot b) =>
      a.segStart < b.segEnd && b.segStart < a.segEnd;

  for (var i = 0; i < n; i++) {
    for (var j = i + 1; j < n; j++) {
      if (overlaps(sorted[i], sorted[j])) union(i, j);
    }
  }

  final maxCol = <int, int>{};
  for (var i = 0; i < n; i++) {
    final r = find(i);
    final c = sorted[i].columnIndex;
    maxCol[r] = maxCol.containsKey(r) ? (maxCol[r]! > c ? maxCol[r]! : c) : c;
  }
  for (var i = 0; i < n; i++) {
    sorted[i].columnCount = maxCol[find(i)]! + 1;
  }

  return [
    for (final s in sorted)
      WeekSlot(
        taskId: s.taskId,
        title: s.title,
        dayIndex: s.dayIndex,
        segStart: s.segStart,
        segEnd: s.segEnd,
        spanStart: s.spanStart,
        spanEnd: s.spanEnd,
        topFrac: s.topFrac,
        heightFrac: s.heightFrac,
        columnIndex: s.columnIndex,
        columnCount: s.columnCount,
      ),
  ];
}
