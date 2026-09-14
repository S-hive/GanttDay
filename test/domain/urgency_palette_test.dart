import 'package:ganttday/domain/gantt/argb_color.dart';
import 'package:ganttday/domain/gantt/urgency_palette.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  const peachArgb = 0xFFFFDAC1;
  const azureArgb = 0xFF457BD9;
  final peachHsl = ArgbColor.toHsl(peachArgb);
  final peachHue = peachHsl.hue.round() % 360;

  test('unfinished uses base swatch S/L even inside former urgency window', () {
    final end = WallClock.minutes(DateTime(2026, 8, 20));
    final far = UrgencyPalette.paint(
      argb: peachArgb,
      plannedStart: end - 60,
      plannedEnd: end,
      now: WallClock.minutes(DateTime(2026, 8, 1)),
      isDone: false,
      urgencyWindowDays: 7,
    );
    final near = UrgencyPalette.paint(
      argb: peachArgb,
      plannedStart: end - 60,
      plannedEnd: end,
      now: end - 60, // almost due
      isDone: false,
      urgencyWindowDays: 7,
    );
    expect(far.planned.saturation, closeTo(peachHsl.saturation, 1e-9));
    expect(far.planned.lightness, closeTo(peachHsl.lightness, 1e-9));
    expect(near.planned.saturation, closeTo(peachHsl.saturation, 1e-9));
    expect(near.planned.lightness, closeTo(peachHsl.lightness, 1e-9));
    expect(near.planned.hue, peachHue);
    expect(far.planned.hatchOverdue, false);
    expect(far.actual, isNull);
  });

  test('overdue unfinished is solid gray without hatch', () {
    final end = WallClock.minutes(DateTime(2026, 8, 8, 12));
    final justOver = UrgencyPalette.paint(
      argb: azureArgb,
      plannedStart: end - 120,
      plannedEnd: end,
      now: end + 60,
      isDone: false,
      urgencyWindowDays: 7,
    );
    final wayOver = UrgencyPalette.paint(
      argb: azureArgb,
      plannedStart: end - 120,
      plannedEnd: end,
      now: end + 10 * 24 * 60,
      isDone: false,
      urgencyWindowDays: 7,
    );
    expect(justOver.planned.isPlannedGray, true);
    expect(justOver.planned.hatchOverdue, false);
    expect(justOver.planned.saturation, 0.12);
    expect(justOver.planned.lightness, 0.55);
    expect(wayOver.planned.isPlannedGray, true);
    expect(wayOver.planned.hatchOverdue, false);
    expect(wayOver.planned.lightness, justOver.planned.lightness);
  });

  test('completed uses gray planned and base-swatch actual', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 9));
    final end = start + 180;
    final p = UrgencyPalette.paint(
      argb: peachArgb,
      plannedStart: start,
      plannedEnd: end,
      now: end + 60,
      isDone: true,
      actualStart: start - 45,
      actualEnd: end + 60,
      urgencyWindowDays: 7,
    );
    expect(p.planned.isPlannedGray, true);
    expect(p.planned.hatchOverdue, false);
    expect(p.actual, isNotNull);
    expect(p.actual!.hatchOverdue, false);
    expect(p.actual!.isPlannedGray, false);
    expect(p.actual!.hue, peachHue);
    expect(p.actual!.saturation, closeTo(peachHsl.saturation, 1e-9));
    expect(p.actual!.lightness, closeTo(peachHsl.lightness, 1e-9));
  });
}
