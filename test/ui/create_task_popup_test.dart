import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/create_task_popup.dart';

void main() {
  testWidgets('create popup confirm returns typed title', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showCreateTaskPopup(
                    context: context,
                    anchorGlobal: const Rect.fromLTWH(40, 80, 120, 20),
                    start: 9 * 60,
                    end: 10 * 60,
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

    expect(find.text('新任务'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '测试任务');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(result, '测试任务');
  });
}
