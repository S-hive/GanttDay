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
}
