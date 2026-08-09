import '../models/gantt_segment.dart';

/// Packs a day's segments into lanes so overlapping tasks stack vertically.
/// Half-open intervals: [a,b) and [b,c) do NOT conflict, so back-to-back
/// tasks (12:00 end / 12:00 start) share a lane (spec section 3).
class LaneLayout {
  LaneLayout._();

  static String keyOf(GanttSegment s) => '${s.taskId}:${s.start}';

  static Map<String, int> assign(List<GanttSegment> segs) {
    final sorted = [...segs]..sort((a, b) {
        final c = a.start.compareTo(b.start);
        return c != 0 ? c : a.end.compareTo(b.end);
      });
    final laneEnds = <int>[]; // exclusive end of the last segment per lane
    final out = <String, int>{};
    for (final s in sorted) {
      var lane = 0;
      while (lane < laneEnds.length && laneEnds[lane] > s.start) {
        lane++;
      }
      if (lane == laneEnds.length) {
        laneEnds.add(s.end);
      } else {
        laneEnds[lane] = s.end;
      }
      out[keyOf(s)] = lane;
    }
    return out;
  }

  static int laneCount(Map<String, int> lanes) =>
      lanes.isEmpty ? 1 : lanes.values.reduce((a, b) => a > b ? a : b) + 1;
}
