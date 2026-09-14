import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/gantt/urgency_palette.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/ui/complete/complete_dialog.dart';

const _refPaint = BarPaint(
  hue: 218,
  saturation: 0.7,
  lightness: 0.55,
  hatchOverdue: false,
  isPlannedGray: false,
);

Task _doneTask() => Task(
      id: 't1',
      title: '午间冥想',
      plannedStart: 12 * 60 + 40,
      plannedEnd: 13 * 60,
      actualStart: 12 * 60 + 45,
      actualEnd: 13 * 60,
      isDone: true,
      createdAt: 0,
    );

void main() {
  testWidgets('secondary tap on blue actual bar returns uncomplete',
      (tester) async {
    CompleteDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCompleteDialog(
                    context,
                    task: _doneTask(),
                    referencePaint: _refPaint,
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('修改实际时间'), findsOneWidget);

    final axis = find.byKey(const Key('complete-axis'));
    expect(axis, findsOneWidget);

    final center = tester.getCenter(axis);
    final gesture = await tester.startGesture(
      center,
      buttons: kSecondaryButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();

    expect(result, isA<CompleteDialogUncomplete>());
  });

  testWidgets('取消完成 button returns uncomplete', (tester) async {
    CompleteDialogResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCompleteDialog(
                    context,
                    task: _doneTask(),
                    referencePaint: _refPaint,
                  );
                },
                child: const Text('open'),
              ),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消完成'));
    await tester.pumpAndSettle();

    expect(result, isA<CompleteDialogUncomplete>());
  });
}
