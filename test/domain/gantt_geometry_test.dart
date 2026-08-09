import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  final day = WallClock.minutes(DateTime(2026, 8, 8));
  final geo = GanttGeometry(
    viewStart: day + 8 * 60,
    viewEnd: day + 22 * 60,
    widthPx: 1400, // 14h => 100px/hour => 25px per 15m
  );

  test('xOf maps viewStart to 0 and viewEnd to width', () {
    expect(geo.xOf(day + 8 * 60), 0);
    expect(geo.xOf(day + 22 * 60), 1400);
  });

  test('timeOf is inverse of xOf at hour marks', () {
    expect(geo.timeOf(100), day + 9 * 60);
  });

  test('snap rounds 8:07 down and 8:08 up', () {
    expect(geo.snap(day + 8 * 60 + 7), day + 8 * 60);
    expect(geo.snap(day + 8 * 60 + 8), day + 8 * 60 + 15);
  });

  test('snap keeps exact quarter marks unchanged', () {
    expect(geo.snap(day + 9 * 60), day + 9 * 60);
    expect(geo.snap(day + 9 * 60 + 45), day + 9 * 60 + 45);
  });

  test('clampDuration enforces 15 minute minimum', () {
    final start = day + 9 * 60;
    expect(geo.clampDuration(start: start, end: start + 5), start + 15);
    expect(geo.clampDuration(start: start, end: start - 30), start + 15);
    expect(geo.clampDuration(start: start, end: start + 45), start + 45);
  });
}
