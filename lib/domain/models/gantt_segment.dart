import '../time/wall_clock.dart';

/// A task's span clipped to a single calendar day (spec: midnight split).
class GanttSegment {
  const GanttSegment({
    required this.taskId,
    required this.start,
    required this.end,
  });

  final String taskId;
  final WallMinutes start;
  final WallMinutes end;
}
