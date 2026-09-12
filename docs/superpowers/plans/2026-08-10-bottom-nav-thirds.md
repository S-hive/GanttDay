# Bottom Nav Thirds Hit Targets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Material `NavigationBar` with a three equal-width icon-only bottom bar so the full left/middle/right thirds switch day/week/month, with minimal selected chrome (icon color only).

**Architecture:** Extract a small `ViewNavBar` widget (`Row` of three `Expanded` ink targets). Shell keeps owning `_navIndex` and passes it in; body mapping is unchanged. Widget tests cover thirds hit targets and selected icon color without booting full `AppShell`.

**Tech Stack:** Flutter/Dart, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-bottom-nav-thirds-design.md`
- Height ≈ 56; icons only (no labels)
- Selected: no Material indicator, no third background fill; selected icon uses `colorScheme.primary`, unselected uses `onSurface` at ~0.45 opacity
- Indices: 0 day / 1 week / 2 month (unchanged)
- Icons: `Icons.view_day_outlined` / `Icons.view_week_outlined` / `Icons.calendar_month_outlined`
- Commit only when the user asks (repo convention); still mark logical commit boundaries per task

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/shell/view_nav_bar.dart` | Equal-thirds icon-only bottom nav |
| `test/ui/view_nav_bar_test.dart` | Hit-target + selected-color widget tests |
| `lib/ui/shell/app_shell.dart` | Use `ViewNavBar` instead of `NavigationBar` |

---

### Task 1: `ViewNavBar` widget (TDD)

**Files:**
- Create: `lib/ui/shell/view_nav_bar.dart`
- Create: `test/ui/view_nav_bar_test.dart`

**Interfaces:**
- Produces:
```dart
class ViewNavBar extends StatelessWidget {
  const ViewNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex; // 0 day, 1 week, 2 month
  final ValueChanged<int> onDestinationSelected;
}
```
- Consumes: none

- [ ] **Step 1: Write the failing tests**

```dart
// test/ui/view_nav_bar_test.dart
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/view_nav_bar_test.dart`

Expected: FAIL — `view_nav_bar.dart` missing / `ViewNavBar` not found

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/shell/view_nav_bar.dart
import 'package:flutter/material.dart';

/// Equal-thirds day/week/month switcher: icon-only, full-height hit targets.
class ViewNavBar extends StatelessWidget {
  const ViewNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  static const double height = 56;

  static const _destinations = <(IconData, String)>[
    (Icons.view_day_outlined, '日'),
    (Icons.view_week_outlined, '周'),
    (Icons.calendar_month_outlined, '月'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedColor = scheme.primary;
    final unselectedColor = scheme.onSurface.withValues(alpha: 0.45);

    return Material(
      color: Theme.of(context).navigationBarTheme.backgroundColor ??
          scheme.surfaceContainer,
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (var i = 0; i < _destinations.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onDestinationSelected(i),
                  child: Semantics(
                    button: true,
                    selected: selectedIndex == i,
                    label: _destinations[i].$2,
                    child: Center(
                      child: Icon(
                        _destinations[i].$1,
                        color: selectedIndex == i
                            ? selectedColor
                            : unselectedColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

Notes:
- Semantic labels stay for a11y but must **not** be visible `Text` widgets (tests assert no visible 日/周/月).
- Prefer `withValues(alpha: 0.45)` (Flutter 3.27+); if analyzer rejects it in this SDK, use `withOpacity(0.45)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/view_nav_bar_test.dart`

Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit (logical boundary; only if user asks)**

```bash
git add lib/ui/shell/view_nav_bar.dart test/ui/view_nav_bar_test.dart
git commit -m "feat(ui): equal-thirds ViewNavBar with icon-only selection"
```

---

### Task 2: Wire `ViewNavBar` into `AppShell`

**Files:**
- Modify: `lib/ui/shell/app_shell.dart` (replace `bottomNavigationBar: NavigationBar(...)`)
- Test: reuse `test/ui/view_nav_bar_test.dart` (no new shell harness required)

**Interfaces:**
- Consumes: `ViewNavBar(selectedIndex:, onDestinationSelected:)`
- Produces: unchanged `_navIndex` → `_buildBody()` mapping

- [ ] **Step 1: Add import**

Near other `../` UI imports in `lib/ui/shell/app_shell.dart`:

```dart
import 'view_nav_bar.dart';
```

- [ ] **Step 2: Replace `NavigationBar` with `ViewNavBar`**

Replace the existing `bottomNavigationBar: NavigationBar(...)` block with:

```dart
      bottomNavigationBar: ViewNavBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
      ),
```

Do **not** change `_buildBody()`, `_navIndex` semantics, AppBar, or drawer wiring.

- [ ] **Step 3: Sanity-check tests still pass**

Run: `flutter test test/ui/view_nav_bar_test.dart`

Expected: PASS

Optional smoke (if convenient): run the app, tap left/middle/right thirds of the bottom bar and confirm day/week/month switch; confirm no pill indicator behind icons.

- [ ] **Step 4: Commit (logical boundary; only if user asks)**

```bash
git add lib/ui/shell/app_shell.dart
git commit -m "feat(shell): use ViewNavBar for day/week/month thirds"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| Three equal thirds, full hit area | Task 1 (`Expanded` + `InkWell`) |
| Icons only, no visible labels | Task 1 (Semantics label only) + test |
| Left/mid/right → day/week/month | Task 1 indices + Task 2 wiring |
| No indicator / no third fill; icon color only | Task 1 colors + test |
| Height ~56 | Task 1 `ViewNavBar.height` |
| Unchanged body mapping | Task 2 leaves `_buildBody` alone |
