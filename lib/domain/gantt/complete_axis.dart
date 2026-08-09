import 'dart:math' as math;

import '../time/wall_clock.dart';

class AxisWindow {
  const AxisWindow({required this.viewStart, required this.viewEnd})
      : assert(viewEnd > viewStart);

  final WallMinutes viewStart;
  final WallMinutes viewEnd;

  int get span => viewEnd - viewStart;
}

/// Axis behavior for the complete dialog (spec section 6):
/// - initial window is the planned span padded by 1 hour each side
/// - while the pointer is down the axis only zooms out / pans, never zooms in
/// - on pointer-up the window settles to a tight fit around the selection
/// - zoom floor: 15 minutes may not shrink below ~8 px; past that the
///   selection is allowed to leave the viewport
class CompleteAxis {
  CompleteAxis._();

  static const int initialPaddingMinutes = 60;
  static const int settlePaddingMinutes = 60;
  static const int dragMarginMinutes = 15;
  static const double minPxPer15Minutes = 8.0;

  static AxisWindow initial({
    required WallMinutes plannedStart,
    required WallMinutes plannedEnd,
  }) {
    return AxisWindow(
      viewStart: plannedStart - initialPaddingMinutes,
      viewEnd: plannedEnd + initialPaddingMinutes,
    );
  }

  /// Widest span (in minutes) the zoom floor allows for [widthPx].
  static int maxMinutesVisible(double widthPx) =>
      math.max(60, (widthPx / minPxPer15Minutes * 15).floor());

  static AxisWindow ensureVisible({
    required AxisWindow current,
    required WallMinutes selStart,
    required WallMinutes selEnd,
    required double widthPx,
    required bool pointerDown,
  }) {
    final maxVisible = maxMinutesVisible(widthPx);
    if (pointerDown) {
      final fits =
          selStart >= current.viewStart && selEnd <= current.viewEnd;
      if (fits) return current;

      var start = math.min(current.viewStart, selStart - dragMarginMinutes);
      var end = math.max(current.viewEnd, selEnd + dragMarginMinutes);
      if (end - start > maxVisible) {
        // Zoom floor hit: keep the widest allowed span (never narrower than
        // the current one) and pan toward the edge being dragged.
        final span = math.max(current.span, maxVisible);
        if (selEnd > current.viewEnd) {
          end = selEnd + dragMarginMinutes;
          start = end - span;
        } else {
          start = selStart - dragMarginMinutes;
          end = start + span;
        }
      }
      return AxisWindow(viewStart: start, viewEnd: end);
    }

    // Settle: tight window around the selection with comfortable padding.
    var start = selStart - settlePaddingMinutes;
    var end = selEnd + settlePaddingMinutes;
    if (end - start > maxVisible) {
      // Center the widest allowed span on the selection; overflow is read
      // via the numeric time labels.
      final center = (selStart + selEnd) ~/ 2;
      start = center - maxVisible ~/ 2;
      end = start + maxVisible;
    }
    return AxisWindow(viewStart: start, viewEnd: end);
  }
}
