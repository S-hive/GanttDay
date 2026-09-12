import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/task/plan_datetime_accordion.dart';

void main() {
  late TextEditingController year;
  late TextEditingController month;
  late TextEditingController day;
  late TextEditingController hour;
  late TextEditingController minute;

  setUp(() {
    year = TextEditingController(text: '2026');
    month = TextEditingController(text: '08');
    day = TextEditingController(text: '10');
    hour = TextEditingController(text: '15');
    minute = TextEditingController(text: '15');
  });

  tearDown(() {
    year.dispose();
    month.dispose();
    day.dispose();
    hour.dispose();
    minute.dispose();
  });

  testWidgets('tap start expands digit fields and 确定; no picker dialog',
      (tester) async {
    var target = PlanEditorTarget.none;
    var confirmed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return PlanDatetimeAccordion(
                startLabel: '2026-08-10 15:15',
                endLabel: '2026-08-10 18:15',
                target: target,
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute,
                onTapStart: () => setState(() {
                  target = target == PlanEditorTarget.start
                      ? PlanEditorTarget.none
                      : PlanEditorTarget.start;
                }),
                onTapEnd: () => setState(() => target = PlanEditorTarget.end),
                onConfirm: () {
                  confirmed = true;
                  setState(() => target = PlanEditorTarget.none);
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('计划开始'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text('确定'), findsOneWidget);
    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.byType(TimePickerDialog), findsNothing);

    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('shows 日期无效 under strip when error set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlanDatetimeAccordion(
            startLabel: '2026-08-10 15:15',
            endLabel: '2026-08-10 18:15',
            target: PlanEditorTarget.start,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            error: '日期无效',
            onTapStart: () {},
            onTapEnd: () {},
            onConfirm: () {},
          ),
        ),
      ),
    );

    expect(find.text('日期无效'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));
    expect(find.text('确定'), findsOneWidget);
  });
}
