import 'package:ganttday/ui/week/week_slot_geometry.dart';
import 'package:test/test.dart';

void main() {
  const dayHeight = 2400.0; // 100 px/hour

  test('uniform inset: top + gap/2, height - gap', () {
    final r = weekBarVerticalRect(
      topFrac: 0.5, // 12:00
      heightFrac: 0.125, // 3 hours → 300 px before inset
      dayHeight: dayHeight,
    );
    expect(r.top, 0.5 * dayHeight + weekVerticalBarGap / 2);
    expect(r.height, 0.125 * dayHeight - weekVerticalBarGap);
  });

  test('abutting bars leave ~verticalBarGap between them', () {
    // 15:00–18:00 then 18:00–19:30
    final a = weekBarVerticalRect(
      topFrac: 15 / 24,
      heightFrac: 3 / 24,
      dayHeight: dayHeight,
    );
    final b = weekBarVerticalRect(
      topFrac: 18 / 24,
      heightFrac: 1.5 / 24,
      dayHeight: dayHeight,
    );
    final gap = b.top - (a.top + a.height);
    expect(gap, closeTo(weekVerticalBarGap, 1e-9));
  });

  test('non-abutting bars still get the same per-bar inset', () {
    final r = weekBarVerticalRect(
      topFrac: 0.1,
      heightFrac: 0.05,
      dayHeight: dayHeight,
    );
    expect(r.top, 0.1 * dayHeight + weekVerticalBarGap / 2);
    expect(r.height, 0.05 * dayHeight - weekVerticalBarGap);
  });

  test('enforces minHeight after inset', () {
    final r = weekBarVerticalRect(
      topFrac: 0,
      heightFrac: 10 / dayHeight, // 10 px raw → 7 after -3
      dayHeight: dayHeight,
    );
    expect(r.height, 18);
  });
}
