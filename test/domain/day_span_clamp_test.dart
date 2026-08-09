import 'package:ganttday/domain/gantt/day_span_clamp.dart';
import 'package:ganttday/domain/gantt/day_visible_range.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  final day0 = WallClock.minutes(DateTime(2026, 8, 8));
  final maxEnd = day0 + kDayViewMaxSpanMinutes;

  test('clampSpanToAxis allows next-day ends within 7 days', () {
    final r = clampSpanToAxis(
      start: day0 + 22 * 60,
      end: day0 + 30 * 60,
      dayAny: day0,
    );
    expect(r.start, day0 + 22 * 60);
    expect(r.end, day0 + 30 * 60);
  });

  test('clampSpanToAxis caps at 7 days', () {
    final r = clampSpanToAxis(
      start: day0 + 20 * 60,
      end: day0 + 10 * WallClock.minutesPerDay,
      dayAny: day0,
    );
    expect(r.end, maxEnd);
  });

  test('clampTimeToAxis stops at axis bounds', () {
    expect(clampTimeToAxis(day0 - 60, day0), day0);
    expect(clampTimeToAxis(maxEnd + 120, day0), maxEnd);
  });
}
