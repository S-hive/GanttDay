# Day Delete Veil Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Double-click a day-view bar to show a full-screen translucent red/green veil; red deletes the task, green or Escape dismisses; single-click still opens the form.

**Architecture:** `DeleteVeil` is two `Expanded` half-screens on `DayGanttPage`'s root `Stack`. `DayBarTapClassifier` decides single-tap vs same-bar double-tap vs cancel-on-slop. `DayGanttGestures` starts bar drag only after `kTouchSlop`. While the veil is open, the timeline is `IgnorePointer`.

**Tech Stack:** Flutter/Dart, `flutter_test`. Spec: `docs/superpowers/specs/2026-09-14-day-delete-veil-design.md`.

## Global Constraints

- Day view only; do not add the veil to week or month
- Veil lives on `DayGanttPage` root `Stack`, not `AppShell`, not `showDialog` / `Overlay`
- Top ARGB `0x73FF8A80`; bottom ARGB `0x7381C784`; alpha must stay `0x73`
- Each half is 50% of the page height; the whole half is the hit target (no text required)
- Double-tap: second pointer-up on the **same** task id opens the veil immediately (no extra 250ms)
- Single-tap opens the form after `kDoubleTapTimeout` (~300ms) if no second tap
- Bar move/resize starts only after movement exceeds `kTouchSlop`; that cancels pending tap/double-tap
- Do not open the veil on pointer-down or while the finger is still down
- Blank long-press (~350ms) create and right-click actual-time stay as they are
- While the veil is open: timeline `IgnorePointer`; no horizontal pan; clicks do not reach Canvas
- Escape while the veil is open ≡ green (dismiss, task remains)
- Delete uses existing `TaskRepository.delete`
- Windows tests: `$env:PROGRAMFILES(X86) = "C:\Program Files (x86)"` then `flutter test …`
- Do not git commit unless the user asks; still record a suggested commit message per task

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/day/delete_veil.dart` | Half-screen colors, `onDelete` / `onCancel` |
| `lib/ui/day/day_bar_tap_classifier.dart` | Same-bar double-tap vs delayed single-tap vs slop cancel |
| `lib/ui/day/day_gantt_gestures.dart` | Slop-before-drag; feed classifier; `onDoubleTapTask` |
| `lib/ui/day/day_gantt_page.dart` | Root Stack + IgnorePointer + Esc + delete |
| `test/ui/delete_veil_test.dart` | Colors, 50% height, callbacks |
| `test/ui/day_bar_tap_classifier_test.dart` | Tap / double-tap / slop / different bars |
| `test/ui/day_gantt_gestures_test.dart` | Widget: delayed tap, double-tap, slop drag |
| `test/ui/day_delete_veil_page_test.dart` | Stack host: IgnorePointer, Esc, red/green |

---

### Task 1: DeleteVeil half-screens

**Files:**
- Create: `lib/ui/day/delete_veil.dart`
- Test: `test/ui/delete_veil_test.dart`

**Interfaces:**
- Consumes: none
- Produces:
  - `const int kDeleteVeilRedArgb = 0x73FF8A80;`
  - `const int kDeleteVeilGreenArgb = 0x7381C784;`
  - `class DeleteVeil extends StatelessWidget { required VoidCallback onDelete; required VoidCallback onCancel; }`
  - Keys: `const Key('delete-veil-red')`, `const Key('delete-veil-green')`

- [ ] **Step 1: Write the failing test**

Create `test/ui/delete_veil_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/delete_veil.dart';

void main() {
  testWidgets('DeleteVeil is two 50% halves with translucent red then green',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DeleteVeil(onDelete: _noop, onCancel: _noop),
        ),
      ),
    );

    final red = tester.getRect(find.byKey(const Key('delete-veil-red')));
    final green = tester.getRect(find.byKey(const Key('delete-veil-green')));
    expect(red.height, 200);
    expect(green.height, 200);
    expect(red.bottom, green.top);

    Color colorOf(Key key) {
      final box = tester.widget<ColoredBox>(
        find.descendant(of: find.byKey(key), matching: find.byType(ColoredBox)),
      );
      return box.color;
    }

    expect(colorOf(const Key('delete-veil-red')), const Color(0x73FF8A80));
    expect(colorOf(const Key('delete-veil-green')), const Color(0x7381C784));
    expect(colorOf(const Key('delete-veil-red')).a, isNot(255));
  });

  testWidgets('tapping anywhere on red/green fires the matching callback',
      (tester) async {
    var deleted = 0;
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DeleteVeil(
            onDelete: () => deleted++,
            onCancel: () => cancelled++,
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 50));
    await tester.tapAt(const Offset(200, 350));
    expect(deleted, 1);
    expect(cancelled, 1);
  });
}

void _noop() {}
```

- [ ] **Step 2: Run test to verify it fails**

Run (PowerShell):

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test test/ui/delete_veil_test.dart
```

Expected: FAIL (library / `DeleteVeil` not found).

- [ ] **Step 3: Write minimal implementation**

Create `lib/ui/day/delete_veil.dart`:

```dart
import 'package:flutter/material.dart';

const int kDeleteVeilRedArgb = 0x73FF8A80;
const int kDeleteVeilGreenArgb = 0x7381C784;

class DeleteVeil extends StatelessWidget {
  const DeleteVeil({
    super.key,
    required this.onDelete,
    required this.onCancel,
  });

  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDelete,
            child: const ColoredBox(
              key: Key('delete-veil-red'),
              color: Color(kDeleteVeilRedArgb),
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: const ColoredBox(
              key: Key('delete-veil-green'),
              color: Color(kDeleteVeilGreenArgb),
            ),
          ),
        ),
      ],
    );
  }
}
```

If the test looks up `ColoredBox` as a descendant of the key, put the `Key` on a parent `SizedBox.expand` wrapping the `ColoredBox`, or put the key on the `ColoredBox` as above and find that widget's color directly:

```dart
expect(
  tester.widget<ColoredBox>(find.byKey(const Key('delete-veil-red'))).color,
  const Color(0x73FF8A80),
);
```

Adjust the test to match this widget tree (key on `ColoredBox`) so it does not require a descendant search.

- [ ] **Step 4: Run test to verify it passes**

Same command as Step 2. Expected: All tests passed.

- [ ] **Step 5: Suggested commit (do not run unless the user asked)**

```
feat: add translucent red/green delete veil
```

---

### Task 2: Same-bar tap classifier and slop-before-drag

**Files:**
- Create: `lib/ui/day/day_bar_tap_classifier.dart`
- Modify: `lib/ui/day/day_gantt_gestures.dart`
- Test: `test/ui/day_bar_tap_classifier_test.dart`
- Test: `test/ui/day_gantt_gestures_test.dart`

**Interfaces:**
- Consumes: `kDoubleTapTimeout`, `kTouchSlop` from `package:flutter/gestures.dart`
- Produces:
  - `class DayBarTapClassifier` with `down(String taskId)`, `movedBeyondSlop()`, `up()`, `dispose()`
  - `DayGanttGestures.onDoubleTapTask` → `void Function(Task task)?`
  - Bar drag starts only after slop; pending tap/double-tap cancelled on slop

- [ ] **Step 1: Write failing classifier tests**

Create `test/ui/day_bar_tap_classifier_test.dart`:

```dart
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/day_bar_tap_classifier.dart';

void main() {
  test('single up then timeout fires onSingleTap once', () {
    final taps = <String>[];
    final doubles = <String>[];
    final c = DayBarTapClassifier(
      onSingleTap: taps.add,
      onDoubleTap: doubles.add,
    );
    c.down('a');
    c.up();
    expect(taps, isEmpty);
    c.elapse(kDoubleTapTimeout);
    expect(taps, ['a']);
    expect(doubles, isEmpty);
    c.dispose();
  });

  test('two ups on same id within timeout fire onDoubleTap immediately', () {
    final taps = <String>[];
    final doubles = <String>[];
    final c = DayBarTapClassifier(
      onSingleTap: taps.add,
      onDoubleTap: doubles.add,
    );
    c.down('a');
    c.up();
    c.down('a');
    c.up();
    expect(doubles, ['a']);
    expect(taps, isEmpty);
    c.elapse(kDoubleTapTimeout);
    expect(taps, isEmpty);
    c.dispose();
  });

  test('second down on a different id is not a double tap', () {
    final taps = <String>[];
    final doubles = <String>[];
    final c = DayBarTapClassifier(
      onSingleTap: taps.add,
      onDoubleTap: doubles.add,
    );
    c.down('a');
    c.up();
    c.down('b');
    c.up();
    expect(doubles, isEmpty);
    c.elapse(kDoubleTapTimeout);
    expect(taps, ['b']);
    c.dispose();
  });

  test('movedBeyondSlop cancels pending tap and double-tap', () {
    final taps = <String>[];
    final doubles = <String>[];
    final c = DayBarTapClassifier(
      onSingleTap: taps.add,
      onDoubleTap: doubles.add,
    );
    c.down('a');
    c.movedBeyondSlop();
    c.up();
    c.elapse(kDoubleTapTimeout);
    expect(taps, isEmpty);
    expect(doubles, isEmpty);
    c.dispose();
  });

  test('up while still waiting for first up does not open on down', () {
    final doubles = <String>[];
    final c = DayBarTapClassifier(
      onSingleTap: (_) {},
      onDoubleTap: doubles.add,
    );
    c.down('a');
    expect(doubles, isEmpty);
    c.dispose();
  });
}
```

`elapse` is part of the classifier so tests do not depend on `FakeAsync` unless you prefer that. Implement `elapse(Duration d)` as `pendingTimer.fire()` using an injected `void Function(Duration, void Function()) schedule` defaulting to `Timer`.

Minimal API the implementation must match:

```dart
class DayBarTapClassifier {
  DayBarTapClassifier({
    required this.onSingleTap,
    required this.onDoubleTap,
    this.timeout = kDoubleTapTimeout,
    void Function(Duration duration, void Function() callback)? schedule,
  });

  void down(String taskId);
  void movedBeyondSlop();
  void up();
  void elapse(Duration duration); // test helper: run due callback now
  void dispose();
}
```

If you inject `schedule`, `elapse` in tests can call the stored callback. Keep `elapse` only if it stays a test seam on the class; alternatively use `fake_async` and drop `elapse`. Prefer `package:fake_async` / `tester.pump` — for this **unit** file, implement timeout with `Timer` and in tests use:

```dart
import 'package:fake_async/fake_async.dart';

fakeAsync((async) {
  c.down('a');
  c.up();
  async.elapse(kDoubleTapTimeout);
});
```

Then **do not** add `elapse` on the classifier. Rewrite the tests above to wrap each case in `fakeAsync` and `async.elapse(...)`. `fake_async` is already a Flutter SDK dependency.

- [ ] **Step 2: Run classifier tests — expect FAIL**

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test test/ui/day_bar_tap_classifier_test.dart
```

Expected: FAIL (file not found).

- [ ] **Step 3: Implement DayBarTapClassifier**

Create `lib/ui/day/day_bar_tap_classifier.dart`:

```dart
import 'dart:async';

import 'package:flutter/gestures.dart';

class DayBarTapClassifier {
  DayBarTapClassifier({
    required this.onSingleTap,
    required this.onDoubleTap,
    this.timeout = kDoubleTapTimeout,
  });

  final void Function(String taskId) onSingleTap;
  final void Function(String taskId) onDoubleTap;
  final Duration timeout;

  String? _downId;
  String? _waitingId;
  bool _slopped = false;
  Timer? _singleTimer;

  void down(String taskId) {
    _downId = taskId;
    _slopped = false;
  }

  void movedBeyondSlop() {
    _slopped = true;
    _downId = null;
    _waitingId = null;
    _singleTimer?.cancel();
    _singleTimer = null;
  }

  void up() {
    if (_slopped || _downId == null) {
      _downId = null;
      return;
    }
    final id = _downId!;
    _downId = null;
    if (_waitingId == id) {
      _singleTimer?.cancel();
      _singleTimer = null;
      _waitingId = null;
      onDoubleTap(id);
      return;
    }
    _singleTimer?.cancel();
    _waitingId = id;
    _singleTimer = Timer(timeout, () {
      _singleTimer = null;
      _waitingId = null;
      onSingleTap(id);
    });
  }

  void dispose() {
    _singleTimer?.cancel();
    _singleTimer = null;
  }
}
```

Different-bar second tap: cancel timer without firing single-tap for `a`, then start a new wait for `b` (as in the test expecting only `['b']`).

- [ ] **Step 4: Classifier tests PASS**

Same command as Step 2.

- [ ] **Step 5: Write failing gesture widget tests**

Add to `test/ui/day_gantt_gestures_test.dart` (keep existing create tests). Helpers:

```dart
import 'package:ganttday/domain/gantt/urgency_palette.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/ui/day/day_gantt_painter.dart';

const _paint = BarPaint(
  hue: 218,
  saturation: 0.7,
  lightness: 0.55,
  hatchOverdue: false,
  isPlannedGray: false,
);

Task _task() => Task(
      id: 't1',
      title: 'deep work',
      plannedStart: 9 * 60,
      plannedEnd: 10 * 60,
      createdAt: 0,
    );

PlacedBar _bar() => PlacedBar(
      taskId: 't1',
      x: 100,
      width: 80,
      lane: 0,
      paint: _paint,
      title: 'deep work',
      isDone: false,
      spanStart: 9 * 60,
      spanEnd: 10 * 60,
    );

Offset barCenter(WidgetTester tester) {
  final origin = tester.getTopLeft(find.byType(DayGanttGestures));
  // lane 0 bar: header 32 + gap 4 + height 20 → center y = 32+4+10
  return origin + const Offset(140, 46);
}
```

Tests:

```dart
testWidgets('single tap on bar opens form after double-tap timeout',
    (tester) async {
  final taps = <String>[];
  final doubles = <String>[];
  await tester.pumpWidget(/* DayGanttGestures with bar + task,
    onTapTask: (t) => taps.add(t.id),
    onDoubleTapTask: (t) => doubles.add(t.id),
    onCreateRange: (_, _, _) {},
    onCommitUpdate: (_) async {},
  */);
  await tester.tapAt(barCenter(tester));
  await tester.pump();
  expect(taps, isEmpty);
  await tester.pump(kDoubleTapTimeout);
  expect(taps, ['t1']);
  expect(doubles, isEmpty);
});

testWidgets('double tap on same bar fires onDoubleTapTask and not onTapTask',
    (tester) async {
  // two tapAt at barCenter with pump() between, no timeout wait
  expect(doubles, ['t1']);
  await tester.pump(kDoubleTapTimeout);
  expect(taps, isEmpty);
});

testWidgets('dragging a bar past slop does not tap or double-tap',
    (tester) async {
  var moved = 0;
  // startGesture at barCenter, moveBy Offset(kTouchSlop + 20, 0), up
  await tester.pump(kDoubleTapTimeout);
  expect(taps, isEmpty);
  expect(doubles, isEmpty);
  expect(moved, 1);
});
```

Pump widget: same `MaterialApp`+`SizedBox(800,400)` pattern as existing tests; pass `bars: [_bar()]`, `tasks: [_task()]`.

- [ ] **Step 6: Run gesture tests — expect FAIL** (tap fires immediately / drag starts on down)

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test test/ui/day_gantt_gestures_test.dart
```

Expected: new tests FAIL (tap happens before timeout, or drag commits on tiny click).

- [ ] **Step 7: Wire classifier and delay bar drag**

In `lib/ui/day/day_gantt_gestures.dart`:

1. Add `final void Function(Task task)? onDoubleTapTask;` to the widget (constructor too).
2. Hold `DayBarTapClassifier? _taps;` created in `initState`, disposed in `dispose`. Callbacks look up `Task` by id from `widget.tasks` and call `onTapTask` / `onDoubleTapTask`.
3. Replace immediate `_beginBarDrag` on pointer down:

```dart
final bar = _barAt(e.localPosition);
if (bar != null && widget.allowBarDrag) {
  _pendingBar = bar;
  final task = _taskOf(bar);
  if (task != null) _taps?.down(task.id);
  return;
}
```

Add field `PlacedBar? _pendingBar;`.

4. In `_onPointerMove`, when `_mode == none` and `_pendingBar != null` and distance from `_downPos` > `kTouchSlop`:

```dart
_taps?.movedBeyondSlop();
_beginBarDrag(_pendingBar!, e.localPosition);
_pendingBar = null;
```

Keep the existing blank-area long-press cancel on slop.

5. In `_finishPointer`, before switching on `_mode`, if `_pendingBar != null` and `_mode == none`:

```dart
_taps?.up();
_pendingBar = null;
```

Then keep the existing move/resize/create finish. Do **not** commit a move when drag never started.

6. Remove `onTapUp` form-open from `GestureDetector` (classifier owns tap). Keep `onSecondaryTapUp` unchanged.

- [ ] **Step 8: Gesture tests PASS; existing create tests still PASS**

Same command as Step 6. Expected: All tests passed.

- [ ] **Step 9: Suggested commit**

```
feat: classify day-bar single tap vs double tap vs drag
```

---

### Task 3: Put the veil on DayGanttPage root Stack

**Files:**
- Modify: `lib/ui/day/day_gantt_page.dart`
- Test: `test/ui/day_delete_veil_page_test.dart`

**Interfaces:**
- Consumes: `DeleteVeil`, `DayGanttGestures.onDoubleTapTask`, `TaskRepository.delete`
- Produces: `String? _deleteVeilTaskId` on the day page; root `Stack`; `IgnorePointer(ignoring: veil open)` around the timeline; Esc dismisses veil first

- [ ] **Step 1: Write failing host tests**

Create `test/ui/day_delete_veil_page_test.dart`. This file tests the **same Stack contract** the page must use (full `DayGanttPage` + sqlite is out of scope). Extract a public wrapper used by the page:

`class DayDeleteVeilStack` in `lib/ui/day/delete_veil.dart` (same file as Task 1, add in this task):

```dart
class DayDeleteVeilStack extends StatelessWidget {
  const DayDeleteVeilStack({
    super.key,
    required this.child,
    required this.veilOpen,
    required this.onDelete,
    required this.onCancel,
  });

  final Widget child;
  final bool veilOpen;
  final VoidCallback onDelete;
  final VoidCallback onCancel;
  ...
}
```

Failing tests **before** adding the wrapper (they import it):

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/delete_veil.dart';

void main() {
  testWidgets('open veil ignores pointers on the child', (tester) async {
    var childTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DayDeleteVeilStack(
            veilOpen: true,
            onDelete: () {},
            onCancel: () {},
            child: GestureDetector(
              onTap: () => childTaps++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(const Offset(200, 50));
    expect(childTaps, 0);
    expect(find.byType(DeleteVeil), findsOneWidget);
  });

  testWidgets('Escape calls onCancel', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 400,
          child: DayDeleteVeilStack(
            veilOpen: true,
            onDelete: () {},
            onCancel: () => cancelled++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(cancelled, 1);
  });
}
```

- [ ] **Step 2: Run — expect FAIL**

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test test/ui/day_delete_veil_page_test.dart
```

Expected: FAIL (`DayDeleteVeilStack` missing).

- [ ] **Step 3: Implement DayDeleteVeilStack**

Add to `lib/ui/day/delete_veil.dart`:

```dart
class DayDeleteVeilStack extends StatelessWidget {
  const DayDeleteVeilStack({
    super.key,
    required this.child,
    required this.veilOpen,
    required this.onDelete,
    required this.onCancel,
  });

  final Widget child;
  final bool veilOpen;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        if (veilOpen)
          const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Focus(
        autofocus: veilOpen,
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(ignoring: veilOpen, child: child),
            if (veilOpen)
              Positioned.fill(
                child: DeleteVeil(onDelete: onDelete, onCancel: onCancel),
              ),
          ],
        ),
      ),
    );
  }
}
```

Import `services.dart` / `widgets.dart` as needed for `CallbackShortcuts` and `LogicalKeyboardKey`.

- [ ] **Step 4: Host tests PASS**

Same command as Step 2.

- [ ] **Step 5: Wire DayGanttPage**

In `lib/ui/day/day_gantt_page.dart`:

1. Import `delete_veil.dart`.
2. Field `String? _deleteVeilTaskId;`.
3. Wrap the existing `CallbackShortcuts` tree with `DayDeleteVeilStack` as the **outermost** widget of `build` (page root), **or** replace the current root so the Stack is the page root:

Current root is `CallbackShortcuts` → `Focus` → `Column(banner, Expanded(gantt))`.

New root:

```dart
return DayDeleteVeilStack(
  veilOpen: _deleteVeilTaskId != null,
  onDelete: _confirmDeleteVeil,
  onCancel: _dismissDeleteVeil,
  child: CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): _exitActualEditMode,
    },
    child: Focus(
      autofocus: editTask != null,
      child: Column( ... existing ... ),
    ),
  ),
);
```

When the veil is open, `DayDeleteVeilStack` already handles Esc and ignores the child, so actual-edit Esc must not steal the key. Give the inner `CallbackShortcuts` Escape binding only when `_deleteVeilTaskId == null`.

4. Pass `onDoubleTapTask: (task) { setState(() => _deleteVeilTaskId = task.id); }` into `DayGanttGestures`.

5. Methods:

```dart
void _dismissDeleteVeil() {
  if (_deleteVeilTaskId == null) return;
  setState(() => _deleteVeilTaskId = null);
}

Future<void> _confirmDeleteVeil() async {
  final id = _deleteVeilTaskId;
  if (id == null) return;
  setState(() => _deleteVeilTaskId = null);
  try {
    await widget.services.tasks.delete(id);
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('删除失败：$e')),
    );
  }
}
```

Do not open the form on double-tap (`onTapTask` stays `widget.onBarTap`).

- [ ] **Step 6: Run covering tests**

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test test/ui/delete_veil_test.dart test/ui/day_bar_tap_classifier_test.dart test/ui/day_gantt_gestures_test.dart test/ui/day_delete_veil_page_test.dart
```

Expected: All tests passed.

Then:

```
${env:PROGRAMFILES(X86)} = "C:\Program Files (x86)"; flutter test
```

Expected: All tests passed (existing create / right-click / actual-edit still green).

- [ ] **Step 7: Suggested commit**

```
feat: show day-view delete veil on double-tap
```

---

## Spec coverage (self-review)

| Spec | Task |
| --- | --- |
| Colors `0x73FF8A80` / `0x7381C784`, 50% halves | 1 |
| Whole half is the hit target | 1 |
| Same-bar double-tap immediate veil, no extra 250ms | 2 + 3 |
| Single-tap form after ~300ms | 2 |
| Different bars ≠ double-tap | 2 |
| Slop → drag, cancel pending taps | 2 |
| No veil on pointer-down / while held | 2 |
| Blank long-press create unchanged | 2 (do not change that path) |
| Right-click actual time unchanged | 2 (keep `onSecondaryTapUp`) |
| Root Stack on day page, not AppShell/Dialog | 3 |
| IgnorePointer while open | 3 |
| Red deletes via `tasks.delete` | 3 |
| Green / Esc dismiss, task remains | 3 |
| Week/month, restore delete dialog, long-press = actual | non-goals, no task |
