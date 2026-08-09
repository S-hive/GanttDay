/// Wall-clock minutes since 1970-01-01 00:00, interpreted in local clock-face
/// terms with no timezone conversion (spec section 4).
typedef WallMinutes = int;

class WallClock {
  WallClock._();

  static const int minutesPerDay = 24 * 60;

  /// Encodes the clock face (year/month/day/hour/minute) as minutes since
  /// 1970-01-01 00:00. Uses UTC arithmetic so the value depends only on the
  /// clock face, never on the machine's current timezone offset.
  static WallMinutes minutes(DateTime local) {
    final utc = DateTime.utc(
        local.year, local.month, local.day, local.hour, local.minute);
    return utc.millisecondsSinceEpoch ~/ 60000;
  }

  /// Decodes wall minutes back to a local [DateTime] with the same clock face.
  static DateTime dateTime(WallMinutes m) {
    final utc = DateTime.fromMillisecondsSinceEpoch(m * 60000, isUtc: true);
    return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  /// 00:00 of the calendar day containing [any].
  static WallMinutes dayStart(WallMinutes any) => any - (any % minutesPerDay);

  /// 00:00 of the next calendar day (exclusive end of the day).
  static WallMinutes dayEndExclusive(WallMinutes any) =>
      dayStart(any) + minutesPerDay;

  /// Current time as wall minutes.
  static WallMinutes now() => minutes(DateTime.now());
}
