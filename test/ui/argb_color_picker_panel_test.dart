import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/argb_color_field.dart';

void main() {
  testWidgets('confirm returns current argb; cancel does not', (tester) async {
    int? confirmed;
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () => cancelled = true,
            svSize: 120,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '#FF0000');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(confirmed, 0xFFFF0000);

    confirmed = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () => cancelled = true,
            svSize: 120,
          ),
        ),
      ),
    );
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(confirmed, isNull);
  });

  testWidgets('illegal hex does not change confirmed color path', (tester) async {
    int? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () {},
            svSize: 120,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(confirmed, 0xFF457BD9);
  });

  testWidgets('omits delete when onDelete is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (_) {},
            onCancel: () {},
            svSize: 120,
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('shows delete on the left and invokes onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (_) {},
            onCancel: () {},
            onDelete: () => deleted = true,
            svSize: 120,
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(deleted, isTrue);
  });
}
