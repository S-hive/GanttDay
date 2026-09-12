import '../models/color_swatch.dart';
import '../time/wall_clock.dart';

/// How one bar should be painted. Pure numbers; the UI maps this to actual
/// Flutter colors (HSL) and hatching.
class BarPaint {
  const BarPaint({
    required this.hue,
    required this.saturation,
    required this.lightness,
    required this.hatchOverdue,
    required this.isPlannedGray,
  });

  final int hue;
  final double saturation;
  final double lightness;
  final bool hatchOverdue;
  final bool isPlannedGray;
}

class TaskPaint {
  const TaskPaint({required this.planned, this.actual});

  final BarPaint planned;
  final BarPaint? actual;
}

/// Bar colors match the resolved swatch (same as tag chips). Overdue unfinished
/// paints gray; completed tasks show a gray planned bar under a swatch-colored
/// actual bar. [urgencyWindowDays] is accepted for API stability but unused.
class UrgencyPalette {
  UrgencyPalette._();

  static TaskPaint paint({
    required ColorSwatch base,
    required WallMinutes plannedStart,
    required WallMinutes plannedEnd,
    required WallMinutes now,
    required bool isDone,
    WallMinutes? actualStart,
    WallMinutes? actualEnd,
    required int urgencyWindowDays,
  }) {
    final baseHue = base.hue;
    final swatchPaint = BarPaint(
      hue: baseHue,
      saturation: base.saturation,
      lightness: base.lightness,
      hatchOverdue: false,
      isPlannedGray: false,
    );
    if (isDone) {
      return TaskPaint(
        planned: BarPaint(
          hue: baseHue,
          saturation: 0.12,
          lightness: 0.55,
          hatchOverdue: false,
          isPlannedGray: true,
        ),
        actual: swatchPaint,
      );
    }
    final remaining = plannedEnd - now;
    if (remaining < 0) {
      // Overdue unfinished: solid gray, same treatment as week/month.
      return TaskPaint(
        planned: BarPaint(
          hue: baseHue,
          saturation: 0.12,
          lightness: 0.55,
          hatchOverdue: false,
          isPlannedGray: true,
        ),
      );
    }
    return TaskPaint(planned: swatchPaint);
  }
}
