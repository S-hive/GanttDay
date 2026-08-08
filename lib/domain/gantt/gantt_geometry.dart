import '../time/wall_clock.dart';

/// Time <-> pixel conversion for a horizontal Gantt axis, plus the 15-minute
/// snap and minimum-duration rules (spec section 3).
class GanttGeometry {
  static const int minDurationMinutes = 15;
  static const int snapMinutes = 15;

  GanttGeometry({
    required this.viewStart,
    required this.viewEnd,
    required this.widthPx,
  })  : assert(viewEnd > viewStart),
        assert(widthPx > 0);

  final WallMinutes viewStart;
  final WallMinutes viewEnd;
  final double widthPx;

  double get _span => (viewEnd - viewStart).toDouble();

  double xOf(WallMinutes t) => (t - viewStart) / _span * widthPx;

  WallMinutes timeOf(double x) => viewStart + ((x / widthPx) * _span).round();

  /// Rounds to the nearest 15 minutes (8:07 -> 8:00, 8:08 -> 8:15).
  WallMinutes snap(WallMinutes t) {
    final r = t % snapMinutes;
    return r < snapMinutes / 2 ? t - r : t + (snapMinutes - r);
  }

  /// Returns an end no earlier than start + 15 minutes; negative or too-short
  /// durations never reach the data layer.
  WallMinutes clampDuration({
    required WallMinutes start,
    required WallMinutes end,
  }) {
    if (end < start + minDurationMinutes) return start + minDurationMinutes;
    return end;
  }
}
