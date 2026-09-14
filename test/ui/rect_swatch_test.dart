import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/rect_swatch.dart';

void main() {
  testWidgets('RectSwatch is 60x30 with zero radius and not a CircleAvatar',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RectSwatch(argb: 0xFF457BD9),
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(RectSwatch)), const Size(60, 30));
    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.zero);
    expect(decoration.border, isNull);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('selected RectSwatch still has no border', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RectSwatch(argb: 0xFF457BD9, selected: true),
          ),
        ),
      ),
    );

    final container = tester.widget<Container>(find.byType(Container));
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.border, isNull);
  });
}
