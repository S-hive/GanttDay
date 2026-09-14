import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/gantt/gantt_geometry.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/day/bar_time_label.dart';
import 'package:ganttday/ui/day/day_gantt_gestures.dart';

void main() {
  final day = WallClock.minutes(DateTime(2026, 8, 8));
  final geo = GanttGeometry(viewStart: day, viewEnd: day + 1440, widthPx: 800);

  Future<void> pumpGestures(
    WidgetTester tester, {
    required void Function(WallMinutes start, WallMinutes end, Rect rect)
    onCreateRange,
    VoidCallback? onSecondaryTapEmpty,
    void Function(WallMinutes? time)? onDragTime,
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
              bars: const [],
              tasks: const [],
              onCommitUpdate: (_) async {},
              onCreateRange: onCreateRange,
              onSecondaryTapEmpty: onSecondaryTapEmpty,
              onDragTime: onDragTime,
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
}
