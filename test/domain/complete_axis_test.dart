import 'package:ganttday/domain/gantt/complete_axis.dart';
import 'package:test/test.dart';

void main() {
  test('initial is planned +/- 60 minutes', () {
    final w = CompleteAxis.initial(plannedStart: 1000, plannedEnd: 1180);
    expect(w.viewStart, 940);
    expect(w.viewEnd, 1240);
  });

  test('dragging past right edge expands and keeps selection inside', () {
    var w = CompleteAxis.initial(plannedStart: 1000, plannedEnd: 1180);
    final selEnd = w.viewEnd + 60; // 1300
    w = CompleteAxis.ensureVisible(
      current: w,
      selStart: 1000,
      selEnd: selEnd,
      widthPx: 600,
      pointerDown: true,
    );
    expect(w.viewEnd, greaterThanOrEqualTo(selEnd));
    expect(w.viewStart, lessThanOrEqualTo(1000));
    expect(w.viewEnd, greaterThan(1240));
  });

  test('dragging past left edge expands leftwards', () {
    var w = CompleteAxis.initial(plannedStart: 1000, plannedEnd: 1180);
    final selStart = w.viewStart - 90; // 850
    w = CompleteAxis.ensureVisible(
      current: w,
      selStart: selStart,
      selEnd: 1180,
      widthPx: 600,
      pointerDown: true,
    );
    expect(w.viewStart, lessThanOrEqualTo(selStart));
    expect(w.viewEnd, greaterThanOrEqualTo(1180));
  });

  test('while dragging, shrinking selection does not shrink axis', () {
    const w = AxisWindow(viewStart: 800, viewEnd: 1600);
    final next = CompleteAxis.ensureVisible(
      current: w,
      selStart: 1000,
      selEnd: 1180,
      widthPx: 600,
      pointerDown: true,
    );
    expect(next.viewStart, 800);
    expect(next.viewEnd, 1600);
  });

  test('on settle, axis recomputes tighter window around selection', () {
    const w = AxisWindow(viewStart: 800, viewEnd: 2000);
    final next = CompleteAxis.ensureVisible(
      current: w,
      selStart: 1000,
      selEnd: 1180,
      widthPx: 600,
      pointerDown: false,
    );
    expect(next.span, lessThan(w.span));
    expect(next.viewStart, lessThanOrEqualTo(1000));
    expect(next.viewEnd, greaterThanOrEqualTo(1180));
  });

  test('zoom floor: axis span never exceeds widthPx/8*15 while dragging', () {
    // width 600 => max 1125 minutes visible
    var w = CompleteAxis.initial(plannedStart: 1000, plannedEnd: 1180);
    w = CompleteAxis.ensureVisible(
      current: w,
      selStart: 1000,
      selEnd: 5000,
      widthPx: 600,
      pointerDown: true,
    );
    expect(w.span, lessThanOrEqualTo(1125));
    // pans toward the dragged (right) edge
    expect(w.viewEnd, greaterThanOrEqualTo(5000));
  });

  test('zoom floor on settle centers on selection', () {
    const w = AxisWindow(viewStart: 0, viewEnd: 6000);
    final next = CompleteAxis.ensureVisible(
      current: w,
      selStart: 1000,
      selEnd: 5000,
      widthPx: 600,
      pointerDown: false,
    );
    expect(next.span, 1125);
    final center = (next.viewStart + next.viewEnd) / 2;
    expect(center, closeTo(3000, 1));
  });
}
