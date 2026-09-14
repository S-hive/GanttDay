import '../time/wall_clock.dart';
import 'argb_color.dart';

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

/// Bar colors match the resolved ARGB (same as tag chips). Overdue unfinished
/// paints gray; completed tasks show a gray planned bar under a color-matched
/// actual bar. [urgencyWindowDays] is accepted for API stability but unused.
class UrgencyPalette {
  UrgencyPalette._();

  static TaskPaint paint({
    required int argb,
    required WallMinutes plannedStart,
    required WallMinutes plannedEnd,
    required WallMinutes now,
    required bool isDone,
    WallMinutes? actualStart,
    WallMinutes? actualEnd,
    required int urgencyWindowDays,
  }) {
    final hsl = ArgbColor.toHsl(argb);
    final baseHue = hsl.hue.round() % 360;
    final swatchPaint = BarPaint(
      hue: baseHue,
      saturation: hsl.saturation,
      lightness: hsl.lightness,
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
