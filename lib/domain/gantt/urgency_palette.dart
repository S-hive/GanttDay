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

/// Color rules from spec section 5: linear urgency toward planned end within
/// a configurable window; overdue caps vividness and adds hatch; completed
/// tasks show a gray planned bar under a single vivid actual bar.
class UrgencyPalette {
  UrgencyPalette._();

  static const double minSaturation = 0.25;
  static const double maxSaturation = 1.0;

  static TaskPaint paint({
    required int baseHue,
    required WallMinutes plannedStart,
    required WallMinutes plannedEnd,
    required WallMinutes now,
    required bool isDone,
    WallMinutes? actualStart,
    WallMinutes? actualEnd,
    required int urgencyWindowDays,
  }) {
    if (isDone) {
      return TaskPaint(
        planned: BarPaint(
          hue: baseHue,
          saturation: 0.12,
          lightness: 0.55,
          hatchOverdue: false,
          isPlannedGray: true,
        ),
        actual: BarPaint(
          hue: baseHue,
          saturation: 0.85,
          lightness: 0.50,
          hatchOverdue: false,
          isPlannedGray: false,
        ),
      );
    }
    final windowMin = urgencyWindowDays * WallClock.minutesPerDay;
    final remaining = plannedEnd - now;
    final overdue = remaining < 0;
    final double t; // 0 = calm, 1 = max urgency (linear within window)
    if (overdue) {
      t = 1;
    } else if (remaining >= windowMin) {
      t = 0;
    } else {
      t = 1 - (remaining / windowMin);
    }
    final sat = minSaturation + (maxSaturation - minSaturation) * t;
    final light = 0.72 - 0.27 * t;
    return TaskPaint(
      planned: BarPaint(
        hue: baseHue,
        saturation: sat,
        lightness: light,
        hatchOverdue: overdue,
        isPlannedGray: false,
      ),
    );
  }
}
