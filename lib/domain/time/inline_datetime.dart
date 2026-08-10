class InlineDateTimeParse {
  InlineDateTimeParse._();

  static DateTime snapToQuarterHour(DateTime dt) {
    final minutes = dt.hour * 60 + dt.minute;
    final snapped = ((minutes + 7) ~/ 15) * 15;
    // Handle 24:00 roll to next day if snapped == 24*60
    if (snapped >= 24 * 60) {
      final next = DateTime(dt.year, dt.month, dt.day).add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day);
    }
    return DateTime(dt.year, dt.month, dt.day, snapped ~/ 60, snapped % 60);
  }

  static ({DateTime? value, String? error}) tryParse({
    required String year,
    required String month,
    required String day,
    required String hour,
    required String minute,
  }) {
    final y = int.tryParse(year.trim());
    final mo = int.tryParse(month.trim());
    final d = int.tryParse(day.trim());
    final h = int.tryParse(hour.trim());
    final mi = int.tryParse(minute.trim());
    if (y == null || mo == null || d == null || h == null || mi == null) {
      return (value: null, error: '日期无效');
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h < 0 || h > 23 || mi < 0 || mi > 59) {
      return (value: null, error: '日期无效');
    }
    final dt = DateTime(y, mo, d, h, mi);
    // DateTime constructor overflows (e.g. Feb 30 → Mar 2); detect mismatch
    if (dt.year != y || dt.month != mo || dt.day != d) {
      return (value: null, error: '日期无效');
    }
    return (value: snapToQuarterHour(dt), error: null);
  }
}
