import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/gantt/urgency_palette.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/day/bar_time_label.dart';
import 'package:ganttday/ui/day/day_gantt_gestures.dart';
import 'package:ganttday/ui/day/day_gantt_painter.dart';

const _paint = BarPaint(
  hue: 218,
  saturation: 0.7,
  lightness: 0.55,
  hatchOverdue: false,
  isPlannedGray: false,
);

Task _task() => Task(
  id: 't1',
  title: 'deep work',
  plannedStart: 9 * 60,
  plannedEnd: 10 * 60,
  createdAt: 0,
);

PlacedBar _bar() => PlacedBar(
  taskId: 't1',
  x: 100,
  width: 80,
  lane: 0,
  paint: _paint,
  title: 'deep work',
  isDone: false,
  spanStart: 9 * 60,
  spanEnd: 10 * 60,
);

Offset barCenter(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(DayGanttGestures));
  // lane 0 bar: header 32 + gap 4 + height 20 → center y = 32+4+10
  return origin + const Offset(140, 46);
}

Offset barLeftEdge(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(DayGanttGestures));
  return origin + const Offset(100, 46);
}

void main() {
  final day = WallClock.minutes(DateTime(2026, 8, 8));
  final geo = GanttGeometry(viewStart: day, viewEnd: day + 1440, widthPx: 800);

  Future<void> pumpGestures(
    WidgetTester tester, {
    required void Function(WallMinutes start, WallMinutes end, Rect rect)
    onCreateRange,
    VoidCallback? onSecondaryTapEmpty,
    void Function(WallMinutes? time)? onDragTime,
    List<PlacedBar> bars = const [],
    List<Task> tasks = const [],
    void Function(Task task)? onTapTask,
    void Function(Task task)? onDoubleTapTask,
    Future<void> Function(Task updated)? onCommitUpdate,
    bool allowBarDrag = true,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: DayGanttGestures(
              canvas: const SizedBox.expand(
                child: ColoredBox(color: Colors.white),
              ),
              geo: geo,
              bars: bars,
              tasks: tasks,
              onCommitUpdate: onCommitUpdate ?? (_) async {},
              onCreateRange: onCreateRange,
              onTapTask: onTapTask,
              onDoubleTapTask: onDoubleTapTask,
              onSecondaryTapEmpty: onSecondaryTapEmpty,
              onDragTime: onDragTime,
              allowBarDrag: allowBarDrag,
            ),
          ),
        ),
      ),
    );
  }

  Offset blankLane(WidgetTester tester) {
    final rect = tester.getRect(find.byType(DayGanttGestures));
    return Offset(rect.left + 100, rect.top + 80);
  }

  testWidgets('create preview shows start, end and duration', (tester) async {
    await pumpGestures(tester, onCreateRange: (_, _, _) {});

    final start = blankLane(tester);
    final primary = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await primary.moveBy(const Offset(150, 0));
    await tester.pump();

    final range = proposeCreate(geo, 100, 250);
    expect(
      find.text(formatBarTimeLabel(range.start, range.end)),
      findsOneWidget,
    );

    await primary.up();
  });

  testWidgets('right-click during create cancels without committing', (
    tester,
  ) async {
    var created = false;
    var emptySecondary = false;
    WallMinutes? dragTime;
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) => created = true,
      onSecondaryTapEmpty: () => emptySecondary = true,
      onDragTime: (time) => dragTime = time,
    );

    final start = blankLane(tester);
    final primary = await tester.startGesture(
      start,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await primary.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(dragTime, isNotNull);

    final secondary = await tester.startGesture(
      start + const Offset(150, 0),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await secondary.up();
    await tester.pump();
    await primary.up();
    await tester.pump();

    expect(created, isFalse);
    expect(emptySecondary, isFalse);
    expect(dragTime, isNull);
  });

  testWidgets('single tap on bar opens form after double-tap timeout', (
    tester,
  ) async {
    final taps = <String>[];
    final doubles = <String>[];
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) {},
      bars: [_bar()],
      tasks: [_task()],
      onTapTask: (t) => taps.add(t.id),
      onDoubleTapTask: (t) => doubles.add(t.id),
    );
    await tester.tapAt(barCenter(tester));
    await tester.pump();
    expect(taps, isEmpty);
    await tester.pump(kDoubleTapTimeout);
    expect(taps, ['t1']);
    expect(doubles, isEmpty);
  });

  testWidgets(
    'double tap on same bar fires onDoubleTapTask and not onTapTask',
    (tester) async {
      final taps = <String>[];
      final doubles = <String>[];
      await pumpGestures(
        tester,
        onCreateRange: (_, _, _) {},
        bars: [_bar()],
        tasks: [_task()],
        onTapTask: (t) => taps.add(t.id),
        onDoubleTapTask: (t) => doubles.add(t.id),
      );
      await tester.tapAt(barCenter(tester));
      await tester.pump();
      await tester.tapAt(barCenter(tester));
      await tester.pump();
      expect(doubles, ['t1']);
      await tester.pump(kDoubleTapTimeout);
      expect(taps, isEmpty);
    },
  );

  testWidgets('dragging a bar past slop does not tap or double-tap', (
    tester,
  ) async {
    final taps = <String>[];
    final doubles = <String>[];
    var moved = 0;
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) {},
      bars: [_bar()],
      tasks: [_task()],
      onTapTask: (t) => taps.add(t.id),
      onDoubleTapTask: (t) => doubles.add(t.id),
      onCommitUpdate: (_) async {
        moved++;
      },
    );
    final gesture = await tester.startGesture(barCenter(tester));
    await gesture.moveBy(Offset(kTouchSlop + 20, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump(kDoubleTapTimeout);
    expect(taps, isEmpty);
    expect(doubles, isEmpty);
    expect(moved, 1);
  });

  testWidgets(
    'drag past slop from bar left edge resizes start, not a whole-bar move',
    (tester) async {
      final original = Task(
        id: 't1',
        title: 'deep work',
        plannedStart: day + 9 * 60,
        plannedEnd: day + 10 * 60,
        createdAt: 0,
      );
      Task? updated;
      await pumpGestures(
        tester,
        onCreateRange: (_, _, _) {},
        bars: [_bar()],
        tasks: [original],
        onCommitUpdate: (t) async {
          updated = t;
        },
      );
      final gesture = await tester.startGesture(barLeftEdge(tester));
      await gesture.moveBy(Offset(kTouchSlop + 20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      expect(updated, isNotNull);
      expect(updated!.plannedStart, isNot(original.plannedStart));
      expect(updated!.plannedEnd, original.plannedEnd);
    },
  );

  testWidgets('pointer cancel on bar does not tap', (tester) async {
    final taps = <String>[];
    final doubles = <String>[];
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) {},
      bars: [_bar()],
      tasks: [_task()],
      onTapTask: (t) => taps.add(t.id),
      onDoubleTapTask: (t) => doubles.add(t.id),
    );
    final gesture = await tester.startGesture(barCenter(tester));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    await tester.pump(kDoubleTapTimeout);
    expect(taps, isEmpty);
    expect(doubles, isEmpty);
  });

  testWidgets('bar tap fires when allowBarDrag is false', (tester) async {
    final taps = <String>[];
    final doubles = <String>[];
    var committed = 0;
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) {},
      bars: [_bar()],
      tasks: [_task()],
      allowBarDrag: false,
      onTapTask: (t) => taps.add(t.id),
      onDoubleTapTask: (t) => doubles.add(t.id),
      onCommitUpdate: (_) async {
        committed++;
      },
    );
    await tester.tapAt(barCenter(tester));
    await tester.pump();
    expect(taps, isEmpty);
    await tester.pump(kDoubleTapTimeout);
    expect(taps, ['t1']);
    expect(doubles, isEmpty);
    expect(committed, 0);
  });

  testWidgets('move below slop does not commit drag', (tester) async {
    var committed = 0;
    await pumpGestures(
      tester,
      onCreateRange: (_, _, _) {},
      bars: [_bar()],
      tasks: [_task()],
      onCommitUpdate: (_) async {
        committed++;
      },
    );
    final gesture = await tester.startGesture(barCenter(tester));
    await gesture.moveBy(Offset(kTouchSlop - 1, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    expect(committed, 0);
  });
}
