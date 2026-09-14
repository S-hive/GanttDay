import 'package:ganttday/domain/gantt/day_gesture_math.dart';
import 'package:ganttday/domain/gantt/day_visible_range.dart';
import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  final day = WallClock.minutes(DateTime(2026, 8, 8));
  final geo = GanttGeometry(
    viewStart: day,
    viewEnd: day + 1440,
    widthPx: 2400,
  );

  Task task({int startHour = 9, int durationMinutes = 120}) => Task(
        id: 't',
        title: 'work',
        plannedStart: day + startHour * 60,
        plannedEnd: day + startHour * 60 + durationMinutes,
        createdAt: 0,
      );

  group('proposeCreate', () {
    test('snaps both ends to quarter hours', () {
      final r = proposeCreate(
          geo, geo.xOf(day + 9 * 60 + 7), geo.xOf(day + 10 * 60 + 8));
      expect(r.start, day + 9 * 60);
      expect(r.end, day + 10 * 60 + 15);
    });
  });

  group('overscroll expand ladder', () {
    test('zero push stays at edge base', () {
      final base = day + 22 * 60;
      final p = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: 100,
        overscrollPx: 0,
        toTheRight: true,
      );
      expect(p, base);
    });

    test('small push opens one hour from fixed base', () {
      final base = day + 22 * 60;
      final hourPx = 100.0;
      final p1 = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: hourPx,
        overscrollPx: 10,
        toTheRight: true,
      );
      expect(p1, base + 60);

      // Same overscroll again → same probe (no runaway).
      final p2 = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: hourPx,
        overscrollPx: 10,
        toTheRight: true,
      );
      expect(p2, p1);
    });

    test('further overscroll opens more hours gradually', () {
      final base = day + 22 * 60;
      final hourPx = 100.0;
      final p = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: hourPx,
        overscrollPx: 250,
        toTheRight: true,
      );
      expect(p, base + 3 * 60);
    });

    test('caps at 7 days', () {
      final base = day + 22 * 60;
      final p = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: 10,
        overscrollPx: 100000,
        toTheRight: true,
      );
      expect(p, day + kDayViewMaxSpanMinutes);
    });

    test('left overscroll opens earlier hours', () {
      final base = day + 8 * 60;
      final p = expandProbeFromOverscroll(
        day0: day,
        maxEnd: day + kDayViewMaxSpanMinutes,
        edgeBase: base,
        hourPx: 100,
        overscrollPx: 150,
        toTheRight: false,
      );
      // hourPx clamped to ≥28 → 150/28 ≈ 6 hours
      expect(p, lessThan(base));
      expect(p, greaterThanOrEqualTo(day));
    });
  });

  group('multi-day create window', () {
    test('create on a multi-day window can end next day', () {
      final fit = GanttGeometry(
        viewStart: day + 20 * 60,
        viewEnd: day + 28 * 60,
        widthPx: 800,
      );
      final r = proposeCreate(fit, 0, fit.widthPx);
      expect(r.end, greaterThan(day + 24 * 60));
      expect(r.end, lessThanOrEqualTo(day + 28 * 60));
    });
  });

  group('proposeMove', () {
    test('keeps duration and snaps', () {
      final moved = proposeMove(task(), geo, 67 / 1440 * 2400);
      expect(moved.plannedStart, day + 10 * 60);
      expect(moved.plannedEnd - moved.plannedStart, 120);
    });
  });
}
