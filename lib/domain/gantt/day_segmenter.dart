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
    if (start >= day1 || end <= day0) return const [];
    final clippedStart = start < day0 ? day0 : start;
    final clippedEnd = end > day1 ? day1 : end;
    if (clippedEnd <= clippedStart) return const [];
    return [GanttSegment(taskId: taskId, start: clippedStart, end: clippedEnd)];
  }
}
