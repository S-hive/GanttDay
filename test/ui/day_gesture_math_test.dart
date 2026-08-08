import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/day/day_gantt_gestures.dart';
import 'package:test/test.dart';

void main() {
  final day = WallClock.minutes(DateTime(2026, 8, 8));
  // 24h over 2400px => 100px/hour, 1px = 0.6min
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
        autoHue: 100,
        createdAt: 0,
      );

  group('proposeCreate', () {
    test('snaps both ends to quarter hours', () {
      // 9:07 -> 9:00, 10:08 -> 10:15
      final r = proposeCreate(geo, geo.xOf(day + 9 * 60 + 7), geo.xOf(day + 10 * 60 + 8));
      expect(r.start, day + 9 * 60);
      expect(r.end, day + 10 * 60 + 15);
    });

    test('works with reversed drag direction', () {
      final r = proposeCreate(geo, geo.xOf(day + 11 * 60), geo.xOf(day + 10 * 60));
      expect(r.start, day + 10 * 60);
      expect(r.end, day + 11 * 60);
    });

    test('tiny drag yields the 15 minute minimum', () {
      final x = geo.xOf(day + 9 * 60);
      final r = proposeCreate(geo, x, x + 1);
      expect(r.end - r.start, 15);
    });
  });

  group('proposeMove', () {
    test('keeps duration and snaps', () {
      // +67 minutes of pixels: 9:00+67 = 10:07 -> snaps to 10:00
      final moved = proposeMove(task(), geo, 67 / 1440 * 2400);
      expect(moved.plannedStart, day + 10 * 60);
      expect(moved.plannedEnd - moved.plannedStart, 120);
    });

    test('moves left too', () {
      final moved = proposeMove(task(), geo, -60 / 1440 * 2400);
      expect(moved.plannedStart, day + 8 * 60);
    });
  });

  group('proposeResizeStart', () {
    test('snaps and keeps end fixed', () {
      final r = proposeResizeStart(task(), geo, geo.xOf(day + 8 * 60 + 8));
      expect(r.plannedStart, day + 8 * 60 + 15);
      expect(r.plannedEnd, day + 11 * 60);
    });

    test('never crosses the end: stops at minimum duration', () {
      final r = proposeResizeStart(task(), geo, geo.xOf(day + 12 * 60));
      expect(r.plannedStart, day + 11 * 60 - 15);
      expect(r.plannedEnd, day + 11 * 60);
    });
  });

  group('proposeResizeEnd', () {
    test('snaps and keeps start fixed', () {
      final r = proposeResizeEnd(task(), geo, geo.xOf(day + 12 * 60 + 7));
      expect(r.plannedEnd, day + 12 * 60);
      expect(r.plannedStart, day + 9 * 60);
    });

    test('never crosses the start: stops at minimum duration', () {
      final r = proposeResizeEnd(task(), geo, geo.xOf(day + 8 * 60));
      expect(r.plannedEnd, day + 9 * 60 + 15);
    });
  });
}
