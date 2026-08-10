# Week Task Vertical Gap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In week view, inset every same-day task bar vertically so adjacent (including time-abutting) bars show at least a 3px gap.

**Architecture:** Keep `layoutWeekSlots` fractions as true time geometry. Apply a uniform pixel inset only when positioning bars in `_slotPositioned`, via a small pure helper that maps `(topFrac, heightFrac, dayHeight)` → `(top, height)`.

**Tech Stack:** Flutter/Dart, `package:test` / `flutter_test` as used by neighboring week tests.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-week-task-vertical-gap-design.md`
- `verticalBarGap = 3` (1.5px top + 1.5px bottom)
- Do not change `layoutWeekSlots` / day / month views
- Preserve existing min bar height of 18 after inset
- Tooltip / span times stay on real `spanStart` / `spanEnd` (no geometry change there)
- Commit only when the user asks (repo convention); still mark logical commit boundaries per task

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/week/week_slot_geometry.dart` | Pure vertical bar inset helper + constant |
| `test/ui/week_slot_geometry_test.dart` | Unit tests for inset / abutting gap |
| `lib/ui/week/week_gantt_page.dart` | Call helper from `_slotPositioned` |

---

### Task 1: Vertical inset helper (TDD)

**Files:**
- Create: `lib/ui/week/week_slot_geometry.dart`
- Create: `test/ui/week_slot_geometry_test.dart`

**Interfaces:**
- Produces:
```dart
const double weekVerticalBarGap = 3;

typedef WeekBarVerticalRect = ({double top, double height});

WeekBarVerticalRect weekBarVerticalRect({
  required double topFrac,
  required double heightFrac,
  required double dayHeight,
  double minHeight = 18,
  double verticalBarGap = weekVerticalBarGap,
});
```
- Consumes: none (pure)

- [ ] **Step 1: Write failing tests**

```dart
// test/ui/week_slot_geometry_test.dart
import 'package:ganttday/ui/week/week_slot_geometry.dart';
import 'package:test/test.dart';

void main() {
  const dayHeight = 2400.0; // 100 px/hour

  test('uniform inset: top + gap/2, height - gap', () {
    final r = weekBarVerticalRect(
      topFrac: 0.5, // 12:00
      heightFrac: 0.125, // 3 hours → 300 px before inset
      dayHeight: dayHeight,
    );
    expect(r.top, 0.5 * dayHeight + weekVerticalBarGap / 2);
    expect(r.height, 0.125 * dayHeight - weekVerticalBarGap);
  });

  test('abutting bars leave ~verticalBarGap between them', () {
    // 15:00–18:00 then 18:00–19:30
    final a = weekBarVerticalRect(
      topFrac: 15 / 24,
      heightFrac: 3 / 24,
      dayHeight: dayHeight,
    );
    final b = weekBarVerticalRect(
      topFrac: 18 / 24,
      heightFrac: 1.5 / 24,
      dayHeight: dayHeight,
    );
    final gap = b.top - (a.top + a.height);
    expect(gap, closeTo(weekVerticalBarGap, 1e-9));
  });

  test('non-abutting bars still get the same per-bar inset', () {
    final r = weekBarVerticalRect(
      topFrac: 0.1,
      heightFrac: 0.05,
      dayHeight: dayHeight,
    );
    expect(r.top, 0.1 * dayHeight + weekVerticalBarGap / 2);
    expect(r.height, 0.05 * dayHeight - weekVerticalBarGap);
  });

  test('enforces minHeight after inset', () {
    final r = weekBarVerticalRect(
      topFrac: 0,
      heightFrac: 10 / dayHeight, // 10 px raw → 7 after -3
      dayHeight: dayHeight,
    );
    expect(r.height, 18);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `dart test test/ui/week_slot_geometry_test.dart`

Expected: FAIL (library / function not found)

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/ui/week/week_slot_geometry.dart

/// Pixel gap between vertically adjacent week task bars (shared by abutting
/// ends: each bar insets by half).
const double weekVerticalBarGap = 3;

typedef WeekBarVerticalRect = ({double top, double height});

/// Maps day-fraction geometry to painted bar top/height with uniform vertical
/// inset. Does not change schedule semantics — only pixels.
WeekBarVerticalRect weekBarVerticalRect({
  required double topFrac,
  required double heightFrac,
  required double dayHeight,
  double minHeight = 18,
  double verticalBarGap = weekVerticalBarGap,
}) {
  final top = topFrac * dayHeight + verticalBarGap / 2;
  var height = heightFrac * dayHeight - verticalBarGap;
  if (height < minHeight) height = minHeight;
  return (top: top, height: height);
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dart test test/ui/week_slot_geometry_test.dart`

Expected: All PASS

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/ui/week/week_slot_geometry.dart test/ui/week_slot_geometry_test.dart
git commit -m "feat(week): pure vertical inset for task bar geometry"
```

---

### Task 2: Wire inset into week `_slotPositioned`

**Files:**
- Modify: `lib/ui/week/week_gantt_page.dart` (`_DayColumn._slotPositioned`)
- Test: reuse `test/ui/week_slot_geometry_test.dart` (no new file required)

**Interfaces:**
- Consumes: `weekBarVerticalRect` / `weekVerticalBarGap` from Task 1
- Produces: week day-column bars positioned with vertical inset; tooltip times unchanged

- [ ] **Step 1: Import the helper**

At the top of `lib/ui/week/week_gantt_page.dart`, add:

```dart
import 'week_slot_geometry.dart';
```

- [ ] **Step 2: Replace raw top/height math in `_slotPositioned`**

Replace:

```dart
    final top = slot.topFrac * dayHeight;
    var height = slot.heightFrac * dayHeight;
    if (height < 18) height = 18;
```

with:

```dart
    final vertical = weekBarVerticalRect(
      topFrac: slot.topFrac,
      heightFrac: slot.heightFrac,
      dayHeight: dayHeight,
    );
    final top = vertical.top;
    final height = vertical.height;
```

Leave left/width, tooltip (`spanStart` / `spanEnd`), InkWell, and decoration unchanged.

- [ ] **Step 3: Run geometry tests + a quick analyze on the page**

Run:

```bash
dart test test/ui/week_slot_geometry_test.dart
dart analyze lib/ui/week/week_gantt_page.dart lib/ui/week/week_slot_geometry.dart
```

Expected: tests PASS; analyze clean (or only pre-existing unrelated warnings)

- [ ] **Step 4: Manual check (optional but recommended)**

Open week view with two same-day abutting tasks (e.g. 15:00–18:00 and 18:00–19:30). Confirm a visible ~3px seam between the colored bars.

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/ui/week/week_gantt_page.dart
git commit -m "feat(week): apply vertical gap between same-day task bars"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| Uniform ±1.5px inset / `verticalBarGap = 3` | Task 1 + 2 |
| Apply in `_slotPositioned`, not layout fractions | Task 2 |
| Keep min height 18 | Task 1 |
| Tooltip / real times unchanged | Task 2 (no span edits) |
| Abutting gap ≈ 3px unit test | Task 1 |
| Week only; no day/month / `week_column_layout` changes | File map + Task 2 scope |
