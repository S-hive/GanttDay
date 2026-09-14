import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/models/default_color.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/ui/common/rect_swatch.dart';
import 'package:ganttday/ui/task/task_form_page.dart';

void main() {
  const tags = [
    Tag(id: 't1', name: '学习', argb: 0xFF457BD9, sortOrder: 0),
    Tag(id: 't2', name: '跳舞', argb: 0xFFE2F0CB, sortOrder: 1),
  ];
  const defaults = [
    DefaultColor(
      id: 'd1',
      argb: 0xFFFFDAC1,
      sortOrder: 0,
      isCurrent: true,
    ),
  ];

  testWidgets('shows 标签 and does not show 主标签 or 附加标签', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagPickList(
            tags: tags,
            selectedId: null,
            onChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('标签'), findsOneWidget);
    expect(find.text('主标签'), findsNothing);
    expect(find.text('附加标签'), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('selecting a tag sets one id; 无 clears it', (tester) async {
    String? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TagPickList(
              tags: tags,
              selectedId: selected,
              onChanged: (id) => setState(() => selected = id),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(selected, 't1');

    await tester.tap(find.text('跳舞'));
    await tester.pump();
    expect(selected, 't2');

    await tester.tap(find.text('无'));
    await tester.pump();
    expect(selected, isNull);

    expect(tester.getSize(find.byType(RectSwatch).first), const Size(60, 30));
    final decoration = tester
        .widget<Container>(find.descendant(
          of: find.byType(RectSwatch).first,
          matching: find.byType(Container),
        ))
        .decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.zero);
  });

  testWidgets(
      'override switch on shows 60x30 chips from tag and default argbs',
      (tester) async {
    int? overrideArgb;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OverrideArgbRow(
              overrideArgb: overrideArgb,
              tags: tags,
              defaults: defaults,
              onChanged: (v) => setState(() => overrideArgb = v),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(RectSwatch), findsNothing);
    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(overrideArgb, 0xFF457BD9);
    expect(find.byType(RectSwatch), findsNWidgets(3));
    expect(tester.getSize(find.byType(RectSwatch).first), const Size(60, 30));
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(CircleAvatar), findsNothing);
  });

  testWidgets('empty tags and defaults with switch on calls picker hook',
      (tester) async {
    int? overrideArgb;
    var pickerCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => OverrideArgbRow(
              overrideArgb: overrideArgb,
              tags: const [],
              defaults: const [],
              pickArgb: (context, {required int initialArgb}) async {
                pickerCalls++;
                return 0xFF112233;
              },
              onChanged: (v) => setState(() => overrideArgb = v),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(pickerCalls, 1);
    expect(overrideArgb, 0xFF112233);
    expect(find.byType(RectSwatch), findsNothing);
  });

  test('saving maps tagId and overrideArgb onto Task', () {
    const existing = Task(
      id: 't1',
      title: 'clip',
      plannedStart: 100,
      plannedEnd: 200,
      createdAt: 1,
    );
    final saved = applyFormPaint(
      existing,
      tagId: 'tg1',
      overrideArgb: 0xFFAA5533,
    );
    expect(saved.tagId, 'tg1');
    expect(saved.overrideArgb, 0xFFAA5533);

    final cleared = applyFormPaint(saved, tagId: null, overrideArgb: null);
    expect(cleared.tagId, isNull);
    expect(cleared.overrideArgb, isNull);
  });
}
