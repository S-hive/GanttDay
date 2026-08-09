import 'package:ganttday/domain/gantt/day_visible_range.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  final day0 = WallClock.minutes(DateTime(2026, 8, 8));

  test('dragging left of fit start expands earlier hours', () {
    final r = expandFitMinutes(
      fitStart: 8 * 60,
      fitEnd: 22 * 60,
      day0: day0,
      time: day0 + 7 * 60 + 30,
    );
    expect(r.start, 7 * 60);
    expect(r.end, 22 * 60);
  });

  test('dragging further left keeps expanding', () {
    final r = expandFitMinutes(
      fitStart: 7 * 60,
      fitEnd: 22 * 60,
      day0: day0,
      time: day0 + 6 * 60,
    );
    expect(r.start, 6 * 60);
  });

  test('dragging past fit end expands later hours', () {
    final r = expandFitMinutes(
      fitStart: 8 * 60,
      fitEnd: 22 * 60,
      day0: day0,
      time: day0 + 22 * 60 + 15,
    );
    expect(r.end, 23 * 60);
  });

  test('past midnight opens the next day', () {
    final r = expandFitMinutes(
      fitStart: 8 * 60,
      fitEnd: 24 * 60,
      day0: day0,
      time: day0 + 24 * 60 + 30,
    );
    expect(r.end, 25 * 60);
  });

  test('keeps expanding across multiple days', () {
    var end = 22 * 60;
    for (var day = 0; day < 3; day++) {
      final r = expandFitMinutes(
        fitStart: 8 * 60,
        fitEnd: end,
        day0: day0,
        time: day0 + end + 30,
      );
      end = r.end;
    }
    expect(end, greaterThan(24 * 60));
    expect(end, lessThanOrEqualTo(kDayViewMaxSpanMinutes));
  });

  test('caps at 7 days', () {
    final r = expandFitMinutes(
      fitStart: 0,
      fitEnd: kDayViewMaxSpanMinutes - 60,
      day0: day0,
      time: day0 + kDayViewMaxSpanMinutes + 120,
    );
    expect(r.end, kDayViewMaxSpanMinutes);
  });

  test('inside window does not change', () {
    final r = expandFitMinutes(
      fitStart: 8 * 60,
      fitEnd: 22 * 60,
      day0: day0,
      time: day0 + 12 * 60,
    );
    expect(r.start, 8 * 60);
    expect(r.end, 22 * 60);
  });

  test('does not open hours before selected day', () {
    final r = expandFitMinutes(
      fitStart: 1 * 60,
      fitEnd: 8 * 60,
      day0: day0,
      time: day0 - 60,
    );
    expect(r.start, 0);
  });

  test('computeDayFitMinutes expands for tasks outside settings', () {
    final r = computeDayFitMinutes(
      settingsStartHour: 8,
      settingsEndHour: 22,
      day0: day0,
      daySpans: [(start: day0 + 6 * 60 + 30, end: day0 + 7 * 60)],
    );
    expect(r.start, 6 * 60);
    expect(r.end, 22 * 60);
  });

  test('computeDayFitMinutes covers multi-day task span', () {
    final r = computeDayFitMinutes(
      settingsStartHour: 8,
      settingsEndHour: 22,
      day0: day0,
      daySpans: [
        (start: day0 + 20 * 60, end: day0 + 26 * 60),
      ],
    );
    expect(r.end, greaterThanOrEqualTo(26 * 60));
  });
}
