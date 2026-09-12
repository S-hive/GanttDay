import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/complete/complete_dialog.dart';
import 'package:test/test.dart';

void main() {
  test('left overflow when sel starts before plan', () {
    final o = CompleteDialogLogic.overflows(
      plannedStart: 100,
      plannedEnd: 200,
      selStart: 80,
      selEnd: 210,
    );
    expect(o.left, (80, 100));
    expect(o.right, (200, 210));
  });

  test('no overflow when selection equals plan', () {
    final o = CompleteDialogLogic.overflows(
      plannedStart: 100,
      plannedEnd: 200,
      selStart: 100,
      selEnd: 200,
    );
    expect(o.left, isNull);
    expect(o.right, isNull);
  });

  test('only left overflow', () {
    final o = CompleteDialogLogic.overflows(
      plannedStart: 100,
      plannedEnd: 200,
      selStart: 50,
      selEnd: 180,
    );
    expect(o.left, (50, 100));
    expect(o.right, isNull);
  });

  test('completely disjoint selection still reports both sides when wrapping',
      () {
    final o = CompleteDialogLogic.overflows(
      plannedStart: 100,
      plannedEnd: 200,
      selStart: 300,
      selEnd: 400,
    );
    expect(o.left, isNull);
    expect(o.right, (200, 400));
  });

  test('selection bar hit includes handle pad', () {
    expect(
      CompleteDialogLogic.hitsSelectionBar(x: 50, selLeft: 40, selRight: 100),
      isTrue,
    );
    expect(
      CompleteDialogLogic.hitsSelectionBar(x: 32, selLeft: 40, selRight: 100),
      isTrue, // within default 8px handle pad
    );
    expect(
      CompleteDialogLogic.hitsSelectionBar(x: 20, selLeft: 40, selRight: 100),
      isFalse,
    );
  });

  test('secondary tap uncompletes only when done and bar is hit', () {
    expect(
      CompleteDialogLogic.shouldUncompleteOnSecondaryTap(
        isDone: true,
        hitSelectionBar: true,
      ),
      isTrue,
    );
    expect(
      CompleteDialogLogic.shouldUncompleteOnSecondaryTap(
        isDone: false,
        hitSelectionBar: true,
      ),
      isFalse,
    );
    expect(
      CompleteDialogLogic.shouldUncompleteOnSecondaryTap(
        isDone: true,
        hitSelectionBar: false,
      ),
      isFalse,
    );
  });

  test('hourMarksFor labels hours like the day view', () {
    final day0 = WallClock.minutes(DateTime(2026, 8, 10));
    final geo = GanttGeometry(
      viewStart: day0 + 9 * 60,
      viewEnd: day0 + 12 * 60,
      widthPx: 600,
    );
    final marks = CompleteDialogLogic.hourMarksFor(
      geo: geo,
      pageDay0: day0,
    );
    expect(marks, isNotEmpty);
    // Day view uses unpadded hour: `${dt.hour}:00`
    expect(marks.map((m) => m.label), containsAll(['9:00', '10:00', '11:00']));
  });
}
