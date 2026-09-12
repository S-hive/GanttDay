import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/gantt/swatch_resolve.dart';
import 'package:ganttday/domain/models/color_swatch.dart';
import 'package:ganttday/ui/settings/swatch_inline_host.dart';

ColorSwatch _s({
  required String id,
  required int argb,
  bool isDefault = false,
}) =>
    colorSwatchFromArgb(
      id: id,
      name: '',
      argb: argb,
      sortOrder: 0,
      isDefault: isDefault,
    );

void main() {
  testWidgets('tap swatch opens inline panel; no AlertDialog', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    expect(find.text('HEX'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('swatch-a')));
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('cancel closes panel without upsert', (tester) async {
    var upserts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async => upserts++,
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('swatch-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsNothing);
    expect(upserts, 0);
  });

  testWidgets('confirm upserts and closes panel', (tester) async {
    ColorSwatch? upserted;
    var upsertCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (s) async {
              upsertCount++;
              upserted = s;
            },
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('swatch-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#FF0000');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(upsertCount, 1);
    expect(upserted!.id, 'a');
    expect(upserted!.argb, 0xFFFF0000);
    expect(find.text('HEX'), findsNothing);
  });

  testWidgets('failed upsert keeps panel open', (tester) async {
    var upsertCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {
              upsertCount++;
              throw Exception('fail');
            },
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('swatch-a')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '#FF0000');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(upsertCount, 1);
    expect(find.text('HEX'), findsOneWidget);
  });

  testWidgets('re-tap same swatch collapses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    final chip = find.byKey(const ValueKey('swatch-a'));
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsNothing);
  });

  testWidgets('edit shows delete; create does not', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [
              _s(id: 'a', argb: 0xFF457BD9, isDefault: true),
              _s(id: 'b', argb: 0xFFFF0000),
            ],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('swatch-b')));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建'));
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsOneWidget);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('sole swatch edit has no delete', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('swatch-a')));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('long-press does not open action sheet', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [
              _s(id: 'a', argb: 0xFF457BD9, isDefault: true),
              _s(id: 'b', argb: 0xFFFF0000),
            ],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (_) async {},
          ),
        ),
      ),
    );
    await tester.longPress(find.byKey(const ValueKey('swatch-b')));
    await tester.pumpAndSettle();
    expect(find.text('设为默认'), findsNothing);
    // Bottom sheet used to show 删除 as a ListTile title even before opening picker.
    expect(find.text('HEX'), findsNothing);
  });

  testWidgets('tapping delete invokes onDelete for edited swatch', (tester) async {
    ColorSwatch? deleted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [
              _s(id: 'a', argb: 0xFF457BD9, isDefault: true),
              _s(id: 'b', argb: 0xFFFF0000),
            ],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
            onSetDefault: (_) async {},
            onDelete: (s) async => deleted = s,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('swatch-b')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted?.id, 'b');
  });

  testWidgets('successful delete closes inline panel', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _DeletableSwatchHost(
            swatches: [
              _s(id: 'a', argb: 0xFF457BD9, isDefault: true),
              _s(id: 'b', argb: 0xFFFF0000),
            ],
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('swatch-b')));
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('HEX'), findsNothing);
    expect(find.byKey(const ValueKey('swatch-b')), findsNothing);
    expect(find.byKey(const ValueKey('swatch-a')), findsOneWidget);
  });
}

class _DeletableSwatchHost extends StatefulWidget {
  const _DeletableSwatchHost({required this.swatches});

  final List<ColorSwatch> swatches;

  @override
  State<_DeletableSwatchHost> createState() => _DeletableSwatchHostState();
}

class _DeletableSwatchHostState extends State<_DeletableSwatchHost> {
  late List<ColorSwatch> _swatches;

  @override
  void initState() {
    super.initState();
    _swatches = List.of(widget.swatches);
  }

  @override
  Widget build(BuildContext context) {
    return SwatchInlineHost(
      swatches: _swatches,
      defaultArgb: 0xFF457BD9,
      onUpsert: (_) async {},
      onSetDefault: (_) async {},
      onDelete: (s) async {
        setState(() => _swatches.removeWhere((x) => x.id == s.id));
      },
    );
  }
}
