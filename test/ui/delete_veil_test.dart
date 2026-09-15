import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/delete_veil.dart';

void main() {
  testWidgets('DeleteVeil is two 50% halves with translucent red then green',
      (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DeleteVeil(onDelete: _noop, onCancel: _noop),
        ),
      ),
    );

    final red = tester.getRect(find.byKey(const Key('delete-veil-red')));
    final green = tester.getRect(find.byKey(const Key('delete-veil-green')));
    expect(red.height, 200);
    expect(green.height, 200);
    expect(red.bottom, green.top);

    final redColor =
        tester.widget<ColoredBox>(find.byKey(const Key('delete-veil-red')))
            .color;
    final greenColor =
        tester.widget<ColoredBox>(find.byKey(const Key('delete-veil-green')))
            .color;

    expect(redColor, const Color(0x73FF8A80));
    expect(greenColor, const Color(0x7381C784));
    expect(redColor.a, const Color(0x73FF8A80).a);
    expect(redColor.a, isNot(1.0));
  });

  testWidgets('tapping anywhere on red/green fires the matching callback',
      (tester) async {
    tester.view.physicalSize = const Size(400, 400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var deleted = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DeleteVeil(
            onDelete: () => deleted++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 50));
    await tester.tapAt(const Offset(200, 350));
    expect(deleted, 1);
    expect(cancelled, 1);
  });
}

void _noop() {}
