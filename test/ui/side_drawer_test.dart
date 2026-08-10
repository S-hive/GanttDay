import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/side_drawer.dart';

void main() {
  testWidgets('opens panel from the right with drawer content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showSideDrawer<void>(
                  context: context,
                  builder: (_) => const Text('drawer-body'),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('drawer-body'), findsOneWidget);
  });

  testWidgets('tapping barrier closes drawer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showSideDrawer<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    width: 200,
                    child: Text('drawer-body'),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('drawer-body'), findsOneWidget);

    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.text('drawer-body'), findsNothing);
  });

  test('sideDrawerWidthFor clamps to 360–480', () {
    expect(sideDrawerWidthFor(500), 360);
    expect(sideDrawerWidthFor(1000), 400);
    expect(sideDrawerWidthFor(2000), 480);
  });
}
