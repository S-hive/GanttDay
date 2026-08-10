import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/gantt/urgency_palette.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:test/test.dart';

void main() {
  final azure = kFactoryColorSwatches.firstWhere((s) => s.id == 'azure');

  test('outside urgency window uses minimum vividness', () {
    final now = WallClock.minutes(DateTime(2026, 8, 1));
    final end = WallClock.minutes(DateTime(2026, 8, 20));
    final p = UrgencyPalette.paint(
      base: azure,
      plannedStart: end - 60,
      plannedEnd: end,
      now: now,
      isDone: false,
      urgencyWindowDays: 7,
    );
    expect(p.planned.saturation, closeTo(azure.saturation, 1e-9));
    expect(p.planned.hatchOverdue, false);
    expect(p.actual, isNull);
  });

  test('urgency grows linearly inside the window', () {
    final end = WallClock.minutes(DateTime(2026, 8, 20));
    double satAt(int daysBefore) => UrgencyPalette.paint(
          base: azure,
          plannedStart: end - 60,
          plannedEnd: end,
          now: end - daysBefore * 24 * 60,
          isDone: false,
          urgencyWindowDays: 7,
        ).planned.saturation;
    final half = satAt(7) + (satAt(0) - satAt(7)) / 2;
    expect(satAt(7), closeTo(azure.saturation, 1e-9));
    expect(satAt(0), closeTo(1.0, 1e-9));
    // linear: 3.5 days out sits exactly halfway
    final at35 = UrgencyPalette.paint(
      base: azure,
      plannedStart: end - 60,
      plannedEnd: end,
      now: end - (7 * 24 * 60) ~/ 2,
      isDone: false,
      urgencyWindowDays: 7,
    ).planned.saturation;
    expect(at35, closeTo(half, 1e-9));
  });

  test('overdue unfinished is solid gray without hatch', () {
    final end = WallClock.minutes(DateTime(2026, 8, 8, 12));
    final justOver = UrgencyPalette.paint(
      base: azure,
      plannedStart: end - 120,
      plannedEnd: end,
      now: end + 60,
      isDone: false,
      urgencyWindowDays: 7,
    );
    final wayOver = UrgencyPalette.paint(
      base: azure,
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

  test('completed returns gray planned and vivid actual without hatch', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 9));
    final end = start + 180;
    final p = UrgencyPalette.paint(
      base: azure,
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
    expect(p.actual!.saturation, greaterThan(0.7));
  });
}
