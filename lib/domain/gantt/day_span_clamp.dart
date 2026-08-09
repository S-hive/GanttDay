import '../time/wall_clock.dart';
import 'day_visible_range.dart';
import 'gantt_geometry.dart';

/// Axis origin day and the latest allowed end (7 days later).
({WallMinutes day0, WallMinutes maxEnd}) dayAxisBounds(WallMinutes dayAny) {
  final day0 = WallClock.dayStart(dayAny);
  return (day0: day0, maxEnd: day0 + kDayViewMaxSpanMinutes);
}

/// Keeps a planned span inside the 7-day day-view axis starting at [dayAny]'s day.
({WallMinutes start, WallMinutes end}) clampSpanToAxis({
  required WallMinutes start,
  required WallMinutes end,
  required WallMinutes dayAny,
  int minDurationMinutes = GanttGeometry.minDurationMinutes,
}) {
  final bounds = dayAxisBounds(dayAny);
  final day0 = bounds.day0;
  final maxEnd = bounds.maxEnd;

  var s = start;
  var e = end;
  if (e < s + minDurationMinutes) e = s + minDurationMinutes;

  if (s < day0) s = day0;
  if (s > maxEnd - minDurationMinutes) s = maxEnd - minDurationMinutes;
  if (e > maxEnd) e = maxEnd;
  if (e < s + minDurationMinutes) {
    e = s + minDurationMinutes;
    if (e > maxEnd) {
      e = maxEnd;
      s = maxEnd - minDurationMinutes;
    }
  }
  return (start: s, end: e);
}

WallMinutes clampTimeToAxis(WallMinutes time, WallMinutes dayAny) {
  final bounds = dayAxisBounds(dayAny);
  if (time < bounds.day0) return bounds.day0;
  if (time > bounds.maxEnd) return bounds.maxEnd;
  return time;
}

/// @nodoc Legacy name — same as [clampSpanToAxis] (multi-day allowed).
({WallMinutes start, WallMinutes end}) clampSpanToDay({
  required WallMinutes start,
  required WallMinutes end,
  required WallMinutes dayAny,
  int minDurationMinutes = GanttGeometry.minDurationMinutes,
}) =>
    clampSpanToAxis(
      start: start,
      end: end,
      dayAny: dayAny,
      minDurationMinutes: minDurationMinutes,
    );

/// @nodoc Legacy name.
WallMinutes clampTimeToDay(WallMinutes time, WallMinutes dayAny) =>
    clampTimeToAxis(time, dayAny);
