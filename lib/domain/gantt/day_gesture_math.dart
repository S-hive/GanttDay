import 'dart:math' as math;

import '../models/task.dart';
import '../time/wall_clock.dart';
import 'day_span_clamp.dart';
import 'gantt_geometry.dart';

/// Calendar-day start for the axis origin containing [geo.viewStart].
({WallMinutes day0, WallMinutes maxEnd}) dayBoundsOf(GanttGeometry geo) =>
    dayAxisBounds(geo.viewStart);

/// Keep gesture x inside the current fitted window `[0, width]`.
double clampXToView(GanttGeometry geo, double x) =>
    x.clamp(0.0, geo.widthPx).toDouble();

/// Snap + clamp a span into the fitted view (⊆ 7-day axis).
({WallMinutes start, WallMinutes end}) clampSpanToView(
  GanttGeometry geo, {
  required WallMinutes start,
  required WallMinutes end,
}) {
  final axis = clampSpanToAxis(
    start: start,
    end: end,
    dayAny: geo.viewStart,
  );
  final minDur = GanttGeometry.minDurationMinutes;
  var s = math.max(axis.start, geo.viewStart);
  var e = math.min(axis.end, geo.viewEnd);
  if (e < s + minDur) {
    e = math.min(geo.viewEnd, s + minDur);
    if (e < s + minDur) {
      s = math.max(geo.viewStart, e - minDur);
    }
  }
  return (start: s, end: e);
}

({WallMinutes start, WallMinutes end}) proposeCreate(
    GanttGeometry geo, double x0, double x1) {
  final left = clampXToView(geo, math.min(x0, x1));
  final right = clampXToView(geo, math.max(x0, x1));
  final start = geo.snap(geo.timeOf(left));
  final end =
      geo.clampDuration(start: start, end: geo.snap(geo.timeOf(right)));
  return clampSpanToView(geo, start: start, end: end);
}

Task proposeMove(Task task, GanttGeometry geo, double deltaX) {
  final duration = task.plannedEnd - task.plannedStart;
  final deltaMinutes =
      (deltaX / geo.widthPx * (geo.viewEnd - geo.viewStart)).round();
  final viewSpan = geo.viewEnd - geo.viewStart;
  if (duration >= viewSpan) {
    final span = clampSpanToView(
      geo,
      start: geo.viewStart,
      end: geo.viewEnd,
    );
    return task.copyWith(
      plannedStart: span.start,
      plannedEnd: span.end,
    );
  }
  final start = geo.snap(task.plannedStart + deltaMinutes);
  final span = clampSpanToView(geo, start: start, end: start + duration);
  if (span.end - span.start == duration) {
    return task.copyWith(plannedStart: span.start, plannedEnd: span.end);
  }
  final maxStart = geo.viewEnd - duration;
  final pinned = start.clamp(geo.viewStart, maxStart);
  return task.copyWith(plannedStart: pinned, plannedEnd: pinned + duration);
}

Task proposeResizeStart(Task task, GanttGeometry geo, double x) {
  var start = geo.snap(geo.timeOf(clampXToView(geo, x)));
  final latest = task.plannedEnd - GanttGeometry.minDurationMinutes;
  if (start > latest) start = latest;
  final span = clampSpanToView(geo, start: start, end: task.plannedEnd);
  return task.copyWith(plannedStart: span.start, plannedEnd: span.end);
}

Task proposeResizeEnd(Task task, GanttGeometry geo, double x) {
  final end = geo.clampDuration(
    start: task.plannedStart,
    end: geo.snap(geo.timeOf(clampXToView(geo, x))),
  );
  final span = clampSpanToView(geo, start: task.plannedStart, end: end);
  return task.copyWith(plannedStart: span.start, plannedEnd: span.end);
}

/// Pixel width of one hour in [geo].
double hourWidthPx(GanttGeometry geo) {
  final spanMin = (geo.viewEnd - geo.viewStart).clamp(1, 7 * 24 * 60);
  return geo.widthPx / (spanMin / 60.0);
}

/// Map edge-push pixels into a probe time.
///
/// [edgeBase] is the view edge when the finger first entered the edge zone;
/// keeping it fixed stops "every frame +1 hour" runaway.
/// Each [hourPx] of push opens one more hour (capped by the 7-day axis).
///
/// [hourPx] is clamped to a desktop-friendly minimum so a short edge zone
/// (when the canvas fills the window and x cannot go <0 / >width) can still
/// open several hours before hold-to-repeat takes over.
WallMinutes expandProbeFromOverscroll({
  required WallMinutes day0,
  required WallMinutes maxEnd,
  required WallMinutes edgeBase,
  required double hourPx,
  required double overscrollPx,
  required bool toTheRight,
}) {
  // ~28px per hour: crossing a 56px edge zone ≈ 2 hours via drag alone.
  final safeHourPx = hourPx.clamp(28.0, 400.0);
  if (overscrollPx <= 0) {
    return clampTimeToAxis(edgeBase, day0);
  }
  final extraHours = math.max(1, (overscrollPx / safeHourPx).ceil());
  final probe = toTheRight
      ? edgeBase + extraHours * 60
      : edgeBase - extraHours * 60;
  return clampTimeToAxis(probe, day0);
}
