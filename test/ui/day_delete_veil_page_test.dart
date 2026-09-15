import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/delete_veil.dart';

void main() {
  testWidgets('open veil ignores pointers on the child', (tester) async {
    var childTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DayDeleteVeilStack(
            veilOpen: true,
            onDelete: () {},
            onCancel: () {},
            child: GestureDetector(
              onTap: () => childTaps++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 50));
    expect(childTaps, 0);
    expect(find.byType(DeleteVeil), findsOneWidget);
    expect(
      tester
          .widget<IgnorePointer>(
            find.descendant(
              of: find.byType(DayDeleteVeilStack),
              matching: find.byType(IgnorePointer),
            ),
          )
          .ignoring,
      isTrue,
    );
  });

  testWidgets('Escape calls onCancel', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DayDeleteVeilStack(
            veilOpen: true,
            onDelete: () {},
            onCancel: () => cancelled++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, 1);
  });
}
