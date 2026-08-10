# Inline Planned DateTime Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace plan start/end date-time picker dialogs in the task form with an inline accordion of prefilled year/month/day/hour/minute fields; re-tap the row commits (15-min snap) and collapses—no Confirm button.

**Architecture:** Pure parse/snap helper in `lib/domain/time/` for testability. `TaskFormPage` owns expand mode (`none|start|end`) and five digit controllers; tapping a plan row toggles expand/commit. Remove `showDatePicker` / `showTimePicker`.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `TaskFormPage` / `WallClock` / `GanttGeometry` snap convention.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-inline-planned-datetime-design.md`
- No `showDatePicker` / `showTimePicker` for plan start/end
- Prefill 年/月/日/时/分; digits only; year maxLength 4, others 2
- Collapse = parse → snap minutes with `(m + 7) ~/ 15 * 15` → update `_start`/`_end`
- Invalid date → keep expanded, show 「日期无效」; no Dialog
- At most one row expanded; switching rows commits current first
- No Confirm button
- Do not change complete-dialog actual-time axis
- Commit only when the user asks; do not run `git commit` unless requested

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/domain/time/inline_datetime.dart` | Parse five ints → DateTime + 15-min snap; error result |
| `test/domain/inline_datetime_test.dart` | Unit tests for parse/snap/invalid |
| `lib/ui/task/task_form_page.dart` | Accordion UI; remove picker dialogs |
| `test/ui/inline_planned_datetime_test.dart` | Widget tests for expand / commit / invalid |

---

### Task 1: Pure parse + 15-minute snap

**Files:**
- Create: `lib/domain/time/inline_datetime.dart`
- Create: `test/domain/inline_datetime_test.dart`

**Interfaces:**
- Produces:
```dart
class InlineDateTimeParse {
  /// null [value] means invalid; [error] is a short Chinese message when null.
  static ({DateTime? value, String? error}) tryParse({
    required String year,
    required String month,
    required String day,
    required String hour,
    required String minute,
  });

  /// Snap clock minutes (hour*60+minute) to nearest 15, return DateTime same YMD.
  static DateTime snapToQuarterHour(DateTime dt);
}
```

- [ ] **Step 1: Write failing unit tests**

```dart
// test/domain/inline_datetime_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/time/inline_datetime.dart';

void main() {
  test('parses valid fields and snaps minutes', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '8', day: '10', hour: '15', minute: '07',
    );
    expect(r.error, isNull);
    expect(r.value, DateTime(2026, 8, 10, 15, 15)); // 07 → 15 via snap inside tryParse
  });

  test('snapToQuarterHour rounds 7→0 and 8→15', () {
    expect(
      InlineDateTimeParse.snapToQuarterHour(DateTime(2026, 1, 1, 10, 7)).minute,
      0,
    );
    expect(
      InlineDateTimeParse.snapToQuarterHour(DateTime(2026, 1, 1, 10, 8)).minute,
      15,
    );
  });

  test('rejects impossible calendar day', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '2', day: '30', hour: '12', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });

  test('rejects non-numeric', () {
    final r = InlineDateTimeParse.tryParse(
      year: '20xx', month: '1', day: '1', hour: '0', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });

  test('rejects hour 24', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '1', day: '1', hour: '24', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });
}
```

Note: `tryParse` **must** call `snapToQuarterHour` on success so UI always stores snapped times.

- [ ] **Step 2: Run — expect FAIL**

```
flutter test test/domain/inline_datetime_test.dart
```

Expected: library/type not found

- [ ] **Step 3: Implement**

```dart
// lib/domain/time/inline_datetime.dart
class InlineDateTimeParse {
  InlineDateTimeParse._();

  static DateTime snapToQuarterHour(DateTime dt) {
    final minutes = dt.hour * 60 + dt.minute;
    final snapped = ((minutes + 7) ~/ 15) * 15;
    // Handle 24:00 roll to next day if snapped == 24*60
    if (snapped >= 24 * 60) {
      final next = DateTime(dt.year, dt.month, dt.day).add(const Duration(days: 1));
      return DateTime(next.year, next.month, next.day);
    }
    return DateTime(dt.year, dt.month, dt.day, snapped ~/ 60, snapped % 60);
  }

  static ({DateTime? value, String? error}) tryParse({
    required String year,
    required String month,
    required String day,
    required String hour,
    required String minute,
  }) {
    final y = int.tryParse(year.trim());
    final mo = int.tryParse(month.trim());
    final d = int.tryParse(day.trim());
    final h = int.tryParse(hour.trim());
    final mi = int.tryParse(minute.trim());
    if (y == null || mo == null || d == null || h == null || mi == null) {
      return (value: null, error: '日期无效');
    }
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h < 0 || h > 23 || mi < 0 || mi > 59) {
      return (value: null, error: '日期无效');
    }
    final dt = DateTime(y, mo, d, h, mi);
    // DateTime constructor overflows (e.g. Feb 30 → Mar 2); detect mismatch
    if (dt.year != y || dt.month != mo || dt.day != d) {
      return (value: null, error: '日期无效');
    }
    return (value: snapToQuarterHour(dt), error: null);
  }
}
```

- [ ] **Step 4: Run — expect PASS**

```
flutter test test/domain/inline_datetime_test.dart
```

- [ ] **Step 5: Commit boundary (skip unless user asks)**

---

### Task 2: Wire accordion into TaskFormPage

**Files:**
- Modify: `lib/ui/task/task_form_page.dart`
- Create: `test/ui/inline_planned_datetime_test.dart`

**Interfaces:**
- Consumes: `InlineDateTimeParse.tryParse` / `snapToQuarterHour`
- Removes: `_pickDateTime` and all `showDatePicker` / `showTimePicker` for plan fields

**State on `_TaskFormPageState`:**
```dart
enum _PlanEditor { none, start, end }
_PlanEditor _planEditor = _PlanEditor.none;
String? _planEditorError; // 「日期无效」 under expand strip
late final TextEditingController _y, _mo, _d, _h, _mi; // dispose in dispose()
```

- [ ] **Step 1: Write failing widget tests (harness without full AppServices)**

Extract a small package-visible widget used by the form **or** test pure UI harness:

```dart
// Prefer creating lib/ui/task/plan_datetime_rows.dart:

class PlanDatetimeRows extends StatelessWidget {
  const PlanDatetimeRows({
    super.key,
    required this.start,
    required this.end,
    required this.fmt,
    required this.editor, // 'none' | 'start' | 'end'
    required this.yearCtrl,
    required this.monthCtrl,
    required this.dayCtrl,
    required this.hourCtrl,
    required this.minuteCtrl,
    this.editorError,
    required this.onToggleStart,
    required this.onToggleEnd,
  });
  // ...
}
```

**Simpler approved approach (less files):** keep logic in `task_form_page.dart` but put **commit helper** as top-level in `inline_datetime.dart` (already Task 1). For widget tests, create:

`lib/ui/task/plan_datetime_accordion.dart` — the two tiles + expand strip; callbacks only.

```dart
enum PlanEditorTarget { none, start, end }

class PlanDatetimeAccordion extends StatelessWidget {
  const PlanDatetimeAccordion({
    super.key,
    required this.startLabel, // formatted start
    required this.endLabel,
    required this.target,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    this.error,
    required this.onTapStart,
    required this.onTapEnd,
  });
  final String startLabel;
  final String endLabel;
  final PlanEditorTarget target;
  final TextEditingController year, month, day, hour, minute;
  final String? error;
  final VoidCallback onTapStart;
  final VoidCallback onTapEnd;
}
```

Widget tests:

```dart
// test/ui/inline_planned_datetime_test.dart
testWidgets('tap start expands digit fields; no date picker route', (tester) async {
  var target = PlanEditorTarget.none;
  final y = TextEditingController(text: '2026');
  final mo = TextEditingController(text: '08');
  final d = TextEditingController(text: '10');
  final h = TextEditingController(text: '15');
  final mi = TextEditingController(text: '15');

  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(builder: (ctx, setState) {
        return PlanDatetimeAccordion(
          startLabel: '2026-08-10 15:15',
          endLabel: '2026-08-10 18:15',
          target: target,
          year: y, month: mo, day: d, hour: h, minute: mi,
          onTapStart: () => setState(() => target =
              target == PlanEditorTarget.start
                  ? PlanEditorTarget.none
                  : PlanEditorTarget.start),
          onTapEnd: () => setState(() => target = PlanEditorTarget.end),
        );
      }),
    ),
  ));

  expect(find.byType(TextField), findsNothing);
  await tester.tap(find.text('计划开始'));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsNWidgets(5));
  expect(find.byType(DatePickerDialog), findsNothing);
  expect(find.byType(TimePickerDialog), findsNothing);
});

testWidgets('shows 日期无效 under strip when error set', (tester) async {
  // pump with error: '日期无效', target start → expect find.text('日期无效')
});
```

Full commit/collapse with parse belongs in TaskFormPage integration; unit tests already cover parse. Optionally add one Stateful harness test that calls `InlineDateTimeParse` on second tap — nice-to-have in same file as a small `_Harness` stateful widget mirroring form toggle logic.

- [ ] **Step 2: Run — expect FAIL** (missing `PlanDatetimeAccordion`)

```
flutter test test/ui/inline_planned_datetime_test.dart
```

- [ ] **Step 3: Implement accordion + wire TaskFormPage**

1. Create `lib/ui/task/plan_datetime_accordion.dart` with ListTiles 「计划开始」「计划结束」, expand strip of 5 digit `TextField`s (FilteringTextInputFormatter.digitsOnly, maxLength 4/2/2/2/2), optional error Text.
2. In `task_form_page.dart`:
   - Add controllers + `_planEditor` + `_planEditorError`
   - `_openPlanEditor(PlanEditorTarget t)` fills controllers from `_start`/`_end`
   - `bool _commitPlanEditor()` → `InlineDateTimeParse.tryParse(...)`; on fail set `_planEditorError` return false; on success set `_start`/`_end`, clear error, set target none, return true
   - `_onTapStart`: if already start → commit; else if other open → commit then open start; else open start
   - Same for end
   - Replace ListTiles with `PlanDatetimeAccordion`
   - Delete `_pickDateTime`
   - In `_save` / `PopScope` before save: if editor open, `_commitPlanEditor()`; if false return (don't close)
3. Dispose the five controllers

- [ ] **Step 4: Run tests**

```
flutter test test/domain/inline_datetime_test.dart test/ui/inline_planned_datetime_test.dart
```

Expected: All passed

- [ ] **Step 5: Commit boundary (skip unless user asks)**

---

### Task 3: Verify acceptance

- [ ] **Step 1: Run focused tests** (command above) — all green
- [ ] **Step 2: Manual** — open task drawer, tap 计划开始, edit minute, tap row again; summary updates; no system picker; invalid Feb 30 stays open with 「日期无效」

---

## Spec coverage

| Spec item | Task |
| --- | --- |
| No date/time dialogs | Task 2 |
| Prefill five fields | Task 2 |
| Re-tap commit + collapse | Task 2 |
| 15-min snap | Task 1 + 2 |
| Invalid keep open + 「日期无效」 | Task 1 + 2 |
| One editor at a time | Task 2 |
| Drawer close commits draft | Task 2 PopScope/`_save` |
| Complete dialog untouched | — |
