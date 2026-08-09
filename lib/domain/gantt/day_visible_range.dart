import '../time/wall_clock.dart';

/// Max span of the day-view axis beyond [day0], in minutes (7 calendar days).
const int kDayViewMaxSpanMinutes = 7 * WallClock.minutesPerDay;

/// Fitted window as minutes from [day0] (hour-aligned).
/// - [start]: ≥ 0 (not before the selected day)
/// - [end]: ≤ [kDayViewMaxSpanMinutes] (may cross into following days)
({int start, int end}) expandFitMinutes({
  required int fitStart,
  required int fitEnd,
  required WallMinutes day0,
  required WallMinutes time,
  bool expandAtExactEnd = true,
}) {
  assert(fitEnd > fitStart);
  var start = fitStart.clamp(0, kDayViewMaxSpanMinutes - 60);
  var end = fitEnd.clamp(60, kDayViewMaxSpanMinutes);
  if (end <= start) end = start + 60;

  final minutes = (time - day0).clamp(0, kDayViewMaxSpanMinutes);

  if (minutes < start) {
    start = (minutes ~/ 60) * 60;
    if (start >= end) start = (end - 60).clamp(0, end - 60);
  }
  if (minutes > end) {
    end = (((minutes + 59) ~/ 60) * 60)
        .clamp(start + 60, kDayViewMaxSpanMinutes);
  } else if (expandAtExactEnd &&
      minutes == end &&
      end < kDayViewMaxSpanMinutes) {
    end = (end + 60).clamp(start + 60, kDayViewMaxSpanMinutes);
  }
  return (start: start, end: end);
}

/// Settings window on the selected day, expanded for task spans / live drag.
/// Returns minute offsets from [day0].
({int start, int end}) computeDayFitMinutes({
  required int settingsStartHour,
  required int settingsEndHour,
  required WallMinutes day0,
  List<({WallMinutes start, WallMinutes end})> daySpans = const [],
  Iterable<WallMinutes> alsoInclude = const [],
}) {
  var start = (settingsStartHour.clamp(0, 23)) * 60;
  var end = (settingsEndHour.clamp(1, 24)) * 60;
  if (end <= start) end = start + 60;

  for (final span in daySpans) {
    if (span.end <= span.start) continue;
    final covered = expandFitMinutes(
      fitStart: start,
      fitEnd: end,
      day0: day0,
      time: span.start,
      expandAtExactEnd: false,
    );
    start = covered.start;
    end = covered.end;
    final last = expandFitMinutes(
      fitStart: start,
      fitEnd: end,
      day0: day0,
      time: span.end - 1,
      expandAtExactEnd: false,
    );
    start = last.start;
    end = last.end;
  }

  for (final probe in alsoInclude) {
    final live = expandFitMinutes(
      fitStart: start,
      fitEnd: end,
      day0: day0,
      time: probe,
    );
    start = live.start;
    end = live.end;
  }

  return (start: start, end: end);
}
