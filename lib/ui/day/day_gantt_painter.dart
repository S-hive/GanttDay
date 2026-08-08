import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/gantt/urgency_palette.dart';

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
    this.actualX,
    this.actualWidth,
    this.actualPaint,
  });

  final String taskId;
  final double x;
  final double width;
  final int lane;
  final BarPaint paint;
  final String title;
  final bool isDone;

  /// Actual-time overlay (completed tasks): thin vivid bar over the gray
  /// planned bar. Null while the task is not done.
  final double? actualX;
  final double? actualWidth;
  final BarPaint? actualPaint;
}

class HourMark {
  const HourMark({required this.x, required this.label, this.emphasized = false});

  final double x;
  final String label;
  final bool emphasized;
}

class DayGanttLayout {
  static const double headerHeight = 28;
  static const double laneHeight = 46;
  static const double barGap = 5;
}

Color colorOf(BarPaint p) {
  if (p.isPlannedGray) {
    return HSLColor.fromAHSL(1, p.hue.toDouble(), 0.06, 0.72).toColor();
  }
  return HSLColor.fromAHSL(
          1, p.hue.toDouble(), p.saturation.clamp(0, 1), p.lightness.clamp(0, 1))
      .toColor();
}

Color borderColorOf(BarPaint p) {
  final base = HSLColor.fromColor(colorOf(p));
  return base.withLightness((base.lightness - 0.16).clamp(0.0, 1.0)).toColor();
}

class DayGanttPainter extends CustomPainter {
  DayGanttPainter({
    required this.bars,
    required this.hourMarks,
    this.todayLineX,
  });

  final List<PlacedBar> bars;
  final List<HourMark> hourMarks;
  final double? todayLineX;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final emphasizedGridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeWidth = 2;

    // Hour grid + header labels.
    for (final mark in hourMarks) {
      canvas.drawLine(
        Offset(mark.x, DayGanttLayout.headerHeight),
        Offset(mark.x, size.height),
        mark.emphasized ? emphasizedGridPaint : gridPaint,
      );
      final tp = TextPainter(
        text: TextSpan(
          text: mark.label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.black.withValues(alpha: 0.55),
            fontWeight: mark.emphasized ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(mark.x + 3, 7));
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
    final height = DayGanttLayout.laneHeight - 2 * DayGanttLayout.barGap;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bar.x + 1, top, math.max(bar.width - 2, 2), height),
      const Radius.circular(6),
    );

    canvas.drawRRect(rect, Paint()..color = colorOf(bar.paint));
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borderColorOf(bar.paint)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    if (bar.paint.hatchOverdue) {
      _paintHatch(canvas, rect.outerRect, borderColorOf(bar.paint));
    }

    // Actual bar overlay: thinner, vivid, centered on the planned lane.
    if (bar.actualX != null && bar.actualWidth != null && bar.actualPaint != null) {
      final actualHeight = height * 0.45;
      final actualRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          bar.actualX! + 1,
          top + (height - actualHeight) / 2,
          math.max(bar.actualWidth! - 2, 2),
          actualHeight,
        ),
        const Radius.circular(4),
      );
      canvas.drawRRect(actualRect, Paint()..color = colorOf(bar.actualPaint!));
      canvas.drawRRect(
        actualRect,
        Paint()
          ..color = borderColorOf(bar.actualPaint!)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final textColor =
        colorOf(bar.paint).computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
    final tp = TextPainter(
      text: TextSpan(
        text: bar.title,
        style: TextStyle(
          fontSize: 12,
          color: textColor,
          decoration: bar.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(bar.width - 12, 0));
    if (bar.width > 24) {
      tp.paint(canvas, Offset(bar.x + 6, top + (height - tp.height) / 2));
    }
  }

  void _paintHatch(Canvas canvas, Rect rect, Color color) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)));
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
        oldDelegate.todayLineX != todayLineX;
  }
}
