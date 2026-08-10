import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/gantt/urgency_palette.dart';
import '../../domain/time/wall_clock.dart';
import 'bar_time_label.dart';

/// A bar fully resolved to pixels and paint — the painter does no time or
/// color math beyond drawing what it is told (spec section 7).
class PlacedBar {
  const PlacedBar({
    required this.taskId,
    required this.x,
    required this.width,
    required this.lane,
    required this.paint,
    required this.title,
    required this.isDone,
    required this.spanStart,
    required this.spanEnd,
    this.notes,
    this.overflowCaption = false,
    this.actualX,
    this.actualWidth,
    this.actualPaint,
  });

  final String taskId;
  final double x;
  final double width;

  /// Row index: one task per row (waterfall day view).
  final int lane;
  final BarPaint paint;
  final String title;
  final bool isDone;
  final WallMinutes spanStart;
  final WallMinutes spanEnd;
  final String? notes;

  /// Day-view overnight stubs: paint title + full span outside a narrow bar.
  final bool overflowCaption;

  /// Inner strip on completed tasks: planned time (outer bar is actual).
  final double? actualX;
  final double? actualWidth;
  final BarPaint? actualPaint;
}

class HourMark {
  const HourMark({
    required this.x,
    required this.label,
    this.emphasized = false,
    this.isDayBoundary = false,
  });

  final double x;
  final String label;
  final bool emphasized;

  /// Midnight of a day other than the selected page day — date in a thin red box.
  final bool isDayBoundary;
}

class DayGanttLayout {
  static const double headerHeight = 32;
  /// Painted bar thickness (px).
  static const double barHeight = 20;
  static const double barGap = 4;
  /// One task row: bar + vertical padding.
  static const double laneHeight = barHeight + 2 * barGap;
}

Color colorOf(BarPaint p) {
  if (p.isPlannedGray) {
    return HSLColor.fromAHSL(1, p.hue.toDouble(), 0.08, 0.78).toColor();
  }
  return HSLColor.fromAHSL(
          1, p.hue.toDouble(), p.saturation.clamp(0, 1), p.lightness.clamp(0, 1))
      .toColor();
}

Color borderColorOf(BarPaint p) {
  final base = HSLColor.fromColor(colorOf(p));
  return base.withLightness((base.lightness - 0.18).clamp(0.0, 1.0)).toColor();
}

Color textColorOn(BarPaint p) {
  final bg = colorOf(p);
  return bg.computeLuminance() > 0.55 ? Colors.black87 : Colors.white;
}

class DayGanttPainter extends CustomPainter {
  DayGanttPainter({
    required this.bars,
    required this.hourMarks,
    required this.rowCount,
    this.todayLineX,
    this.viewportLeft = 0,
    this.viewportWidth = double.infinity,
  });

  final List<PlacedBar> bars;
  final List<HourMark> hourMarks;
  final int rowCount;
  final double? todayLineX;

  /// Horizontal scroll offset (content x of the viewport's left edge).
  final double viewportLeft;

  /// Visible width of the timeline viewport in px.
  final double viewportWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final hourPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final rowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    for (var r = 0; r <= rowCount; r++) {
      final y = DayGanttLayout.headerHeight + r * DayGanttLayout.laneHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    for (final mark in hourMarks) {
      canvas.drawLine(
        Offset(mark.x, DayGanttLayout.headerHeight),
        Offset(mark.x, size.height),
        mark.emphasized ? hourPaint : gridPaint,
      );
      if (mark.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: mark.label,
            style: TextStyle(
              fontSize: 11,
              color: mark.isDayBoundary
                  ? const Color(0xFFC62828)
                  : Colors.black.withValues(alpha: 0.55),
              fontWeight:
                  mark.emphasized ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final textOrigin = Offset(mark.x + 4, 8);
        if (mark.isDayBoundary) {
          const padX = 3.0;
          const padY = 1.5;
          final box = RRect.fromRectAndRadius(
            Rect.fromLTWH(
              textOrigin.dx - padX,
              textOrigin.dy - padY,
              tp.width + padX * 2,
              tp.height + padY * 2,
            ),
            const Radius.circular(2),
          );
          canvas.drawRRect(
            box,
            Paint()
              ..color = const Color(0xFFC62828)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1,
          );
        }
        tp.paint(canvas, textOrigin);
      }
    }

    if (hourMarks.length >= 2) {
      final hourPx = hourMarks[1].x - hourMarks[0].x;
      if (hourPx > 40) {
        final qPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.04)
          ..strokeWidth = 1;
        for (var i = 0; i < hourMarks.length - 1; i++) {
          final base = hourMarks[i].x;
          for (var q = 1; q < 4; q++) {
            final x = base + hourPx * q / 4;
            canvas.drawLine(
              Offset(x, DayGanttLayout.headerHeight),
              Offset(x, size.height),
              qPaint,
            );
          }
        }
      }
    }

    for (final bar in bars) {
      _paintBar(canvas, bar);
    }

    if (todayLineX != null) {
      final nowPaint = Paint()
        ..color = Colors.redAccent
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(todayLineX!, DayGanttLayout.headerHeight - 4),
        Offset(todayLineX!, size.height),
        nowPaint,
      );
    }
  }

  void _paintBar(Canvas canvas, PlacedBar bar) {
    final top = DayGanttLayout.headerHeight +
        bar.lane * DayGanttLayout.laneHeight +
        DayGanttLayout.barGap;
    final height = DayGanttLayout.barHeight;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bar.x + 1, top, math.max(bar.width - 2, 2), height),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      rect.shift(const Offset(0, 1.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );

    canvas.drawRRect(rect, Paint()..color = colorOf(bar.paint));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borderColorOf(bar.paint).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    if (bar.paint.hatchOverdue) {
      _paintHatch(canvas, rect.outerRect, borderColorOf(bar.paint));
    }

    if (bar.actualX != null &&
        bar.actualWidth != null &&
        bar.actualPaint != null) {
      final actualHeight = height * 0.28;
      final actualRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bar.actualX! + 1,
          top + height - actualHeight + 2,
          math.max(bar.actualWidth! - 2, 2),
          actualHeight,
        ),
        const Radius.circular(3),
      );
      canvas.drawRRect(
          actualRect, Paint()..color = colorOf(bar.actualPaint!));
    }

    _paintBarCaption(canvas, bar, rect.outerRect);
  }

  /// One line: bold title + time range + duration (+ optional notes).
  /// Always paints the full caption; may extend past the bar's right edge.
  /// Caption X is sticky: max(barLeft, viewportLeft), so long bars keep their
  /// labels readable while scrolling.
  ///
  /// When the caption overflows the bar, paints a dark underlayer first, then
  /// the on-bar foreground clipped to [rect] — bar-interior stays high-contrast
  /// on the fill; overflow stays readable on the light grid.
  void _paintBarCaption(Canvas canvas, PlacedBar bar, Rect rect) {
    final viewportRight = viewportLeft + viewportWidth;
    // Fully off-screen → skip.
    if (rect.right <= viewportLeft || rect.left >= viewportRight) return;

    final fg = textColorOn(bar.paint);
    final muted = fg.withValues(alpha: 0.78);
    final timeText = formatBarTimeLabel(bar.spanStart, bar.spanEnd);
    final notes = bar.notes?.trim();
    final hasNotes = notes != null && notes.isNotEmpty;

    const titleSize = 13.0;
    const metaSize = 11.0;

    TextPainter buildLine(Color titleColor, Color metaColor) {
      return TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: bar.title,
              style: TextStyle(
                fontSize: titleSize,
                fontWeight: FontWeight.w700,
                color: titleColor,
                height: 1.15,
              ),
            ),
            TextSpan(
              text: '  $timeText',
              style: TextStyle(
                fontSize: metaSize,
                fontWeight: FontWeight.w500,
                color: metaColor,
                height: 1.15,
              ),
            ),
            if (hasNotes)
              TextSpan(
                text: ' · $notes',
                style: TextStyle(
                  fontSize: metaSize,
                  fontWeight: FontWeight.w500,
                  color: metaColor,
                  height: 1.15,
                ),
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
    }

    final line = buildLine(fg, muted);

    final textX = stickyCaptionLeft(
      barLeft: rect.left,
      barRight: rect.right,
      viewportLeft: viewportLeft,
      captionWidth: line.width,
    );
    final offset = Offset(
      textX,
      rect.top + (rect.height - line.height) / 2,
    );

    final overflows = captionOverflowsBar(
      textX: textX,
      captionWidth: line.width,
      barLeft: rect.left,
      barRight: rect.right,
    );
    if (!overflows) {
      line.paint(canvas, offset);
      return;
    }

    // Outside: dark on light grid; inside: on-bar foreground clipped to bar.
    const outsideFg = Color(0xDE000000); // ~black87
    final outside = buildLine(outsideFg, outsideFg.withValues(alpha: 0.78));
    outside.paint(canvas, offset);
    canvas.save();
    canvas.clipRect(rect);
    line.paint(canvas, offset);
    canvas.restore();
  }

  void _paintHatch(Canvas canvas, Rect rect, Color color) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));
    final paint = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 2;
    const step = 9.0;
    for (var x = rect.left - rect.height; x < rect.right; x += step) {
      canvas.drawLine(
        Offset(x, rect.bottom),
        Offset(x + rect.height, rect.top),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(DayGanttPainter oldDelegate) {
    return oldDelegate.bars != bars ||
        oldDelegate.hourMarks != hourMarks ||
        oldDelegate.rowCount != rowCount ||
        oldDelegate.todayLineX != todayLineX ||
        oldDelegate.viewportLeft != viewportLeft ||
        oldDelegate.viewportWidth != viewportWidth;
  }
}
