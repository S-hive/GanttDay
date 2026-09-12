import 'dart:math' as math;

import '../../domain/time/wall_clock.dart';

/// What a day-view bar caption should paint given available space.
class BarCaptionMode {
  const BarCaptionMode({
    required this.showTitle,
    required this.showMeta,
    required this.clipToBar,
  });

  final bool showTitle;
  final bool showMeta;

  /// When false, title (and optional meta) may paint outside the bar rect.
  final bool clipToBar;
}

/// Day-view captions always paint full title + start–end（duration）
/// (and notes when present), never clipped/ellipsized to the bar width.
BarCaptionMode resolveBarCaptionMode({
  required bool canStack,
  required bool overflowCaption,
}) {
  // [canStack] / [overflowCaption] kept for call-site compatibility; day view
  // no longer drops meta or clips to the bar for short spans.
  return const BarCaptionMode(
    showTitle: true,
    showMeta: true,
    clipToBar: false,
  );
}

/// True when [end] falls on a later calendar day than [start]
/// (exclusive end at exactly 00:00 does not count as spanning).
bool spansMultipleCalendarDays(WallMinutes start, WallMinutes end) {
  if (end <= start) return false;
  return WallClock.dayStart(start) != WallClock.dayStart(end - 1);
}

/// True when the laid-out caption extends past either horizontal edge of the bar.
bool captionOverflowsBar({
  required double textX,
  required double captionWidth,
  required double barLeft,
  required double barRight,
}) {
  return textX < barLeft || textX + captionWidth > barRight;
}

/// Horizontal sticky caption origin (content coords):
/// `max(barLeft, viewportLeft)`, clamped so the caption leaves with the bar's
/// right edge when the viewport scrolls past the end of the bar.
double stickyCaptionLeft({
  required double barLeft,
  required double barRight,
  required double viewportLeft,
  required double captionWidth,
  double padding = 7,
}) {
  final minLeft = barLeft + padding;
  var left = math.max(minLeft, viewportLeft + padding);
  final maxLeft = barRight - padding - captionWidth;
  if (maxLeft > minLeft) {
    left = math.min(left, maxLeft);
  }
  return left;
}

/// Plain one-line caption: `任务名  09:00 – 10:30（1h 30m）`.
String formatBarInlineCaption(
  String title,
  WallMinutes start,
  WallMinutes end,
) =>
    '$title  ${formatBarTimeLabel(start, end)}';

const _weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];

/// `8月 4日 (星期二)`.
String formatBarHoverDate(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return '${d.month}月 ${d.day}日 (星期${_weekdayNames[d.weekday - 1]})';
}

/// Hover subtitle: `8月 4日 (星期二) · 09:00 – 10:30（1h 30m）`.
String formatBarHoverMeta({
  required WallMinutes start,
  required WallMinutes end,
  DateTime? focusDay,
}) {
  final day = focusDay ?? WallClock.dateTime(WallClock.dayStart(start));
  return '${formatBarHoverDate(day)} · ${formatBarTimeLabel(start, end)}';
}

/// Hover card: title + date · start–end（duration）.
String formatBarHoverDetail({
  required String title,
  required WallMinutes start,
  required WallMinutes end,
  DateTime? focusDay,
}) =>
    '$title\n${formatBarHoverMeta(start: start, end: end, focusDay: focusDay)}';

/// Formats bar time meta: `09:00 – 10:30（1h 30m）`.
/// Cross-midnight spans use `次日` on the end clock face.
String formatBarTimeLabel(WallMinutes start, WallMinutes end) {
  String hhmm(WallMinutes m) {
    final dt = WallClock.dateTime(m);
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  final mins = end - start;
  final endLabel = spansMultipleCalendarDays(start, end)
      ? '次日 ${hhmm(end)}'
      : hhmm(end);
  return '${hhmm(start)} – $endLabel（${formatDurationMinutes(mins)}）';
}

String formatDurationMinutes(int minutes) {
  if (minutes < 0) minutes = 0;
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

/// Create/drag preview meta prefers sitting above the bar; flips below when
/// the top slot would be clipped, and stays above when the bottom slot would.
bool previewMetaLabelAbove({
  required double barTop,
  required double barBottom,
  required double labelExtent,
  required double clipTop,
  required double clipBottom,
}) {
  final aboveFits = barTop - labelExtent >= clipTop;
  if (aboveFits) return true;
  final belowFits = barBottom + labelExtent <= clipBottom;
  if (belowFits) return false;
  return true;
}
