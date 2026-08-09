import '../models/gantt_segment.dart';
import '../models/task.dart';
import '../time/wall_clock.dart';

/// Clips a task's planned span to one calendar day. A midnight-spanning task
/// is stored as one record but drawn as one segment per day; a task ending
/// exactly at 00:00 produces nothing on the next day (spec section 3).
class DaySegmenter {
  DaySegmenter._();

  static List<GanttSegment> segmentsForDay(Task task, WallMinutes dayAny) {
    return clipToDay(
      taskId: task.id,
      start: task.plannedStart,
      end: task.plannedEnd,
      dayAny: dayAny,
    );
  }

  /// Same clipping for an arbitrary span (used for actual bars too).
  static List<GanttSegment> clipToDay({
    required String taskId,
    required WallMinutes start,
    required WallMinutes end,
    required WallMinutes dayAny,
  }) {
    final day0 = WallClock.dayStart(dayAny);
    final day1 = WallClock.dayEndExclusive(dayAny);
    return clipToRange(
      taskId: taskId,
      start: start,
      end: end,
      rangeStart: day0,
      rangeEnd: day1,
    );
  }

  /// Clip a span to an arbitrary half-open range `[rangeStart, rangeEnd)`.
  /// Used by week view to keep overnight tasks as one continuous bar.
  static List<GanttSegment> clipToRange({
    required String taskId,
    required WallMinutes start,
    required WallMinutes end,
    required WallMinutes rangeStart,
    required WallMinutes rangeEnd,
  }) {
    if (start >= rangeEnd || end <= rangeStart) return const [];
    final clippedStart = start < rangeStart ? rangeStart : start;
    final clippedEnd = end > rangeEnd ? rangeEnd : end;
    if (clippedEnd <= clippedStart) return const [];
    return [
      GanttSegment(taskId: taskId, start: clippedStart, end: clippedEnd),
    ];
  }
}
