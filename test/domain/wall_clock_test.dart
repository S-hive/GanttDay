import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  test('round-trip local DateTime without shifting clock face', () {
    final dt = DateTime(2026, 8, 8, 9, 15);
    final m = WallClock.minutes(dt);
    final back = WallClock.dateTime(m);
    expect(back.year, 2026);
    expect(back.month, 8);
    expect(back.day, 8);
    expect(back.hour, 9);
    expect(back.minute, 15);
  });

  test('dayStart and dayEndExclusive bound a calendar day', () {
    final noon = WallClock.minutes(DateTime(2026, 8, 8, 12, 0));
    final start = WallClock.dayStart(noon);
    final end = WallClock.dayEndExclusive(noon);
    expect(WallClock.dateTime(start), DateTime(2026, 8, 8));
    expect(WallClock.dateTime(end), DateTime(2026, 8, 9));
    expect(end - start, 24 * 60);
  });

  test('encoding depends only on the clock face, not the timezone', () {
    // 9:00 must encode to the same value however the local offset is set:
    // minutes = full days since epoch * 1440 + minutes within the day.
    final m = WallClock.minutes(DateTime(2026, 8, 8, 9, 0));
    final daysSinceEpoch =
        DateTime.utc(2026, 8, 8).difference(DateTime.utc(1970, 1, 1)).inDays;
    expect(m, daysSinceEpoch * 1440 + 9 * 60);
  });

  test('midnight is its own dayStart', () {
    final mid = WallClock.minutes(DateTime(2026, 8, 8));
    expect(WallClock.dayStart(mid), mid);
    expect(WallClock.dayEndExclusive(mid), mid + 1440);
  });
}
