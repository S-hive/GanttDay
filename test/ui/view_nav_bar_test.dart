import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/shell/view_nav_bar.dart';

void main() {
  testWidgets('tapping each third selects that index', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ViewNavBar(
            selectedIndex: 0,
            onDestinationSelected: selected.add,
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byType(ViewNavBar));
    final y = bar.center.dy;
    final w = bar.width;

    await tester.tapAt(Offset(bar.left + w * 0.1, y));
    await tester.pump();
    await tester.tapAt(Offset(bar.left + w * 0.5, y));
    await tester.pump();
    await tester.tapAt(Offset(bar.left + w * 0.9, y));
    await tester.pump();

    expect(selected, [0, 1, 2]);
  });

  testWidgets('tapping near top of each third selects that index', (tester) async {
    final selected = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ViewNavBar(
            selectedIndex: 0,
            onDestinationSelected: selected.add,
          ),
        ),
      ),
    );

    final bar = tester.getRect(find.byType(ViewNavBar));
    final y = bar.top + 4;
    final w = bar.width;

    await tester.tapAt(Offset(bar.left + w * 0.1, y));
    await tester.pump();
    await tester.tapAt(Offset(bar.left + w * 0.5, y));
    await tester.pump();
    await tester.tapAt(Offset(bar.left + w * 0.9, y));
    await tester.pump();

    expect(selected, [0, 1, 2]);
  });

  testWidgets('selected icon uses primary; others are muted', (tester) async {
    const primary = Color(0xFF3366FF);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: primary).copyWith(
            primary: primary,
          ),
        ),
        home: Scaffold(
          bottomNavigationBar: ViewNavBar(
            selectedIndex: 1,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    IconData iconOf(Finder f) => tester.widget<Icon>(f).icon!;
    Color? colorOf(Finder f) => tester.widget<Icon>(f).color;

    final day = find.byIcon(Icons.view_day_outlined);
    final week = find.byIcon(Icons.view_week_outlined);
    final month = find.byIcon(Icons.calendar_month_outlined);

    expect(iconOf(day), Icons.view_day_outlined);
    expect(iconOf(week), Icons.view_week_outlined);
    expect(iconOf(month), Icons.calendar_month_outlined);

    expect(colorOf(week), primary);
    expect(colorOf(day), isNot(primary));
    expect(colorOf(month), isNot(primary));
    expect(colorOf(day)!.opacity, lessThan(1.0));
  });

  testWidgets('has no NavigationBar / destination labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          bottomNavigationBar: ViewNavBar(
            selectedIndex: 0,
            onDestinationSelected: (_) {},
          ),
        ),
      ),
    );

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('日'), findsNothing);
    expect(find.text('周'), findsNothing);
    expect(find.text('月'), findsNothing);
  });
}
