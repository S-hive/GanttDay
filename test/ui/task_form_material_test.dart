import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/side_drawer.dart';

void main() {
  testWidgets('MaterialPageRoute without Material reports No Material on TextField',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SizedBox(
                      width: 400,
                      height: 800,
                      child: Column(
                        children: [
                          Expanded(
                            child: ListView(
                              children: [
                                TextField(
                                  decoration: const InputDecoration(
                                    labelText: '任务名',
                                    border: OutlineInputBorder(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
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
    FlutterError.onError = old;

    expect(
      errors.any((e) => e.toString().contains('No Material widget found')),
      isTrue,
      reason: 'expected Material missing error; got: $errors',
    );
  });

  testWidgets('Material wrap on route page hosts TextField', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Material(
                      child: SizedBox(
                        width: 400,
                        height: 800,
                        child: Column(
                          children: [
                            Expanded(
                              child: ListView(
                                children: [
                                  TextField(
                                    decoration: const InputDecoration(
                                      labelText: '任务名',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
    FlutterError.onError = old;

    expect(
      errors.where((e) => e.toString().contains('No Material widget found')),
      isEmpty,
    );
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('side drawer hosts TextField without Material error',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showSideDrawer<void>(
                  context: context,
                  builder: (_) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(labelText: '任务名'),
                    ),
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
    FlutterError.onError = old;

    expect(
      errors.where((e) => e.toString().contains('No Material widget found')),
      isEmpty,
    );
    expect(find.byType(TextField), findsOneWidget);
  });
}
