# Tag Filter AppBar Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move tag filtering from the day/week body chip row into an AppBar menu (left of Settings), with a badge when active, and apply the same filter to day, week, and month.

**Architecture:** Extract a pure `taskMatchesTagFilter` helper (primary ∪ attached tags; empty set = show all). Day/week/month call it after loading `tagIdsForTask`. Shell owns `_filterTagIds` and a `MenuAnchor` filter icon; body chip row is removed.

**Tech Stack:** Flutter/Dart, existing `TaskRepository.tagIdsForTask`, `flutter_test` / `package:test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-tag-filter-appbar-menu-design.md`
- Match rule: primary tag **or** any attached tag id; empty `filterTagIds` = all tasks
- No persistence of filter across app restarts
- No settings-page tag CRUD changes
- Month overflow/layout: reuse existing `selectVisibleMonthTasks` on the **already filtered** list
- Commit only when the user asks (repo convention); still mark logical commit boundaries per task

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/domain/gantt/tag_filter.dart` | Pure match helper |
| `test/domain/tag_filter_test.dart` | Unit tests for match helper |
| `lib/ui/day/day_gantt_page.dart` | Use shared helper |
| `lib/ui/week/week_gantt_page.dart` | Load attached tags + shared helper |
| `lib/ui/month/month_page.dart` | Accept `filterTagIds`, load attached tags, filter before layout |
| `lib/ui/shell/app_shell.dart` | Remove body chips; AppBar filter `MenuAnchor` + badge; pass filter to month |

---

### Task 1: Shared tag filter helper (TDD)

**Files:**
- Create: `lib/domain/gantt/tag_filter.dart`
- Create: `test/domain/tag_filter_test.dart`

**Interfaces:**
- Produces:
```dart
bool taskMatchesTagFilter({
  required String? primaryTagId,
  required List<String> attachedTagIds,
  required Set<String> filterTagIds,
})
```
- Consumes: none (pure)

- [ ] **Step 1: Write failing tests**

```dart
// test/domain/tag_filter_test.dart
import 'package:ganttday/domain/gantt/tag_filter.dart';
import 'package:test/test.dart';

void main() {
  test('empty filter matches everything', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: null,
        attachedTagIds: const [],
        filterTagIds: const {},
      ),
      isTrue,
    );
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'a',
        attachedTagIds: const ['b'],
        filterTagIds: const {},
      ),
      isTrue,
    );
  });

  test('matches primary tag', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const [],
        filterTagIds: {'work'},
      ),
      isTrue,
    );
  });

  test('matches attached tag without primary', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: null,
        attachedTagIds: const ['life'],
        filterTagIds: {'life'},
      ),
      isTrue,
    );
  });

  test('matches attached tag when primary differs', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const ['life'],
        filterTagIds: {'life'},
      ),
      isTrue,
    );
  });

  test('rejects when neither primary nor attached hits', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const ['life'],
        filterTagIds: {'sport'},
      ),
      isFalse,
    );
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `dart test test/domain/tag_filter_test.dart`
Expected: FAIL (library / function missing)

- [ ] **Step 3: Implement helper**

```dart
// lib/domain/gantt/tag_filter.dart
bool taskMatchesTagFilter({
  required String? primaryTagId,
  required List<String> attachedTagIds,
  required Set<String> filterTagIds,
}) {
  if (filterTagIds.isEmpty) return true;
  if (primaryTagId != null && filterTagIds.contains(primaryTagId)) {
    return true;
  }
  return attachedTagIds.any(filterTagIds.contains);
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `dart test test/domain/tag_filter_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/domain/gantt/tag_filter.dart test/domain/tag_filter_test.dart
git commit -m "feat: add shared tag filter match helper"
```

---

### Task 2: Day + week use shared match rule

**Files:**
- Modify: `lib/ui/day/day_gantt_page.dart` (`_visibleTasks`)
- Modify: `lib/ui/week/week_gantt_page.dart` (load `tagIdsForTask`, replace `_filtered`)

**Interfaces:**
- Consumes: `taskMatchesTagFilter` from Task 1
- Produces: day/week both honor primary ∪ attached tags

- [ ] **Step 1: Update day `_visibleTasks`**

Add import:
```dart
import '../../domain/gantt/tag_filter.dart';
```

Replace getter body:
```dart
List<Task> get _visibleTasks {
  return _tasks
      .where(
        (t) => taskMatchesTagFilter(
          primaryTagId: t.primaryTagId,
          attachedTagIds: _taskTagIds[t.id] ?? const <String>[],
          filterTagIds: widget.filterTagIds,
        ),
      )
      .toList();
}
```

- [ ] **Step 2: Week — store attached tag ids**

In `_WeekGanttPageState`, add:
```dart
Map<String, List<String>> _taskTagIds = const {};
```

In `_subscribe` listen callback, after loading tags/swatches, also:
```dart
final tagIds = <String, List<String>>{};
for (final t in tasks) {
  tagIds[t.id] = await widget.services.tasks.tagIdsForTask(t.id);
}
```
and set `_taskTagIds = tagIds` in `setState`.

Add import for `tag_filter.dart`.

Replace `_filtered`:
```dart
List<Task> get _filtered {
  return _tasks
      .where(
        (t) => taskMatchesTagFilter(
          primaryTagId: t.primaryTagId,
          attachedTagIds: _taskTagIds[t.id] ?? const <String>[],
          filterTagIds: widget.filterTagIds,
        ),
      )
      .toList();
}
```

In `didUpdateWidget`, when only `filterTagIds` changes, **do not** need to re-subscribe to the task stream — current code re-subscribes on filter change which still works (wasteful but correct). Prefer: only re-subscribe when `anchorDate` changes; for `filterTagIds` change call `setState` only (filter is a getter). Minimal fix:

```dart
@override
void didUpdateWidget(WeekGanttPage oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.anchorDate != widget.anchorDate) {
    _didInitialScroll = false;
    _subscribe();
  } else if (oldWidget.filterTagIds != widget.filterTagIds) {
    setState(() {});
  }
}
```

- [ ] **Step 3: Verify analyzer on touched files**

Run: `dart analyze lib/ui/day/day_gantt_page.dart lib/ui/week/week_gantt_page.dart lib/domain/gantt/tag_filter.dart`
Expected: No issues

- [ ] **Step 4: Commit (only if user asked)**

```bash
git add lib/ui/day/day_gantt_page.dart lib/ui/week/week_gantt_page.dart
git commit -m "fix: unify day/week tag filter to primary or attached tags"
```

---

### Task 3: Month view consumes `filterTagIds`

**Files:**
- Modify: `lib/ui/month/month_page.dart`

**Interfaces:**
- Consumes: `taskMatchesTagFilter`; `AppServices.tasks.tagIdsForTask`
- Produces: `MonthPage({ ..., Set<String> filterTagIds = const {} })`

- [ ] **Step 1: Add constructor field + state**

```dart
class MonthPage extends StatefulWidget {
  const MonthPage({
    super.key,
    required this.services,
    required this.month,
    required this.onOpenDay,
    this.filterTagIds = const {},
  });

  final AppServices services;
  final DateTime month;
  final void Function(DateTime day) onOpenDay;
  final Set<String> filterTagIds;
  // ...
}
```

In state:
```dart
Map<String, List<String>> _taskTagIds = const {};
```

Import `tag_filter.dart`.

- [ ] **Step 2: Load attached tags in `_subscribe`**

Same pattern as week: for each task in the stream snapshot, `tagIdsForTask`, store in `_taskTagIds`.

- [ ] **Step 3: `didUpdateWidget`**

```dart
@override
void didUpdateWidget(MonthPage oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.month != widget.month) {
    _subscribe();
  } else if (oldWidget.filterTagIds != widget.filterTagIds) {
    setState(() {});
  }
}
```

- [ ] **Step 4: Filter before layout**

```dart
@override
Widget build(BuildContext context) {
  final filtered = _tasks
      .where(
        (t) => taskMatchesTagFilter(
          primaryTagId: t.primaryTagId,
          attachedTagIds: _taskTagIds[t.id] ?? const <String>[],
          filterTagIds: widget.filterTagIds,
        ),
      )
      .toList();
  final selected = selectVisibleMonthTasks(
    month: _monthStart,
    tasks: filtered,
  );
  // ... rest unchanged, still using selected.visible / overflowByDay
}
```

- [ ] **Step 5: Analyze**

Run: `dart analyze lib/ui/month/month_page.dart`
Expected: No issues

- [ ] **Step 6: Commit (only if user asked)**

```bash
git add lib/ui/month/month_page.dart
git commit -m "feat: apply tag filter in month view"
```

---

### Task 4: App shell — AppBar filter menu, remove body chips

**Files:**
- Modify: `lib/ui/shell/app_shell.dart`

**Interfaces:**
- Consumes: `MonthPage.filterTagIds` from Task 3
- Produces: filter entry left of Settings; no body chip row

- [ ] **Step 1: Remove body chip row**

Delete the `if (_tags.isNotEmpty && _navIndex != 2) Padding(... Wrap FilterChip ...)` block under `body: Column`. Body becomes:

```dart
body: _buildBody(),
```

(or `body: Column(children: [Expanded(child: _buildBody())])` only if something else still needs Column — prefer flat `body: _buildBody()`).

- [ ] **Step 2: Pass filter into month**

```dart
case 2:
  return ExcludeSemantics(
    child: MonthPage(
      services: widget.services,
      month: _date,
      filterTagIds: _filterTagIds,
      onOpenDay: (day) => setState(() {
        _date = day;
        _navIndex = 0;
      }),
    ),
  );
```

- [ ] **Step 3: Add filter `MenuAnchor` left of Settings**

In `actions`, **before** the settings `IconButton`:

```dart
actions: [
  if (_tags.isNotEmpty)
    MenuAnchor(
      builder: (context, controller, child) {
        return IconButton(
          tooltip: '标签筛选',
          onPressed: () {
            if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          },
          icon: Badge(
            isLabelVisible: _filterTagIds.isNotEmpty,
            smallSize: 8,
            child: const Icon(Icons.filter_list),
          ),
        );
      },
      menuChildren: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('全部'),
                  selected: _filterTagIds.isEmpty,
                  onSelected: (_) => setState(() => _filterTagIds = {}),
                ),
                for (final tag in _tags)
                  FilterChip(
                    label: Text(tag.name),
                    selected: _filterTagIds.contains(tag.id),
                    avatar: CircleAvatar(
                      backgroundColor: _tagColor(tag.swatchId),
                      radius: 8,
                    ),
                    onSelected: (sel) => setState(() {
                      final next = {..._filterTagIds};
                      if (sel) {
                        next.add(tag.id);
                      } else {
                        next.remove(tag.id);
                      }
                      _filterTagIds = next;
                    }),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  IconButton(
    icon: const Icon(Icons.settings_outlined),
    tooltip: '',
    onPressed: _openSettings,
  ),
],
```

Notes for implementer:
- Prefer Material `Badge` with `isLabelVisible` + `smallSize` (dot). If theme makes the badge a fat pill, set `label: const SizedBox.shrink()` or use a `Stack` + 6–8px `CircleAvatar`/`Container` top-right instead — keep a **small theme-colored dot**.
- Multi-select must stay open while tapping chips. If `MenuAnchor` closes on chip tap, switch to `OverlayPortal` / custom overlay with a full-screen transparent barrier that closes on outside tap; keep the same chip UI.
- Filter icon visible on day/week/**month** whenever `_tags.isNotEmpty`.

- [ ] **Step 4: Analyze shell**

Run: `dart analyze lib/ui/shell/app_shell.dart`
Expected: No issues

- [ ] **Step 5: Manual acceptance checklist**

- [ ] Day/week: no top chip row; timeline taller
- [ ] Settings left: filter icon; opens chip menu; outside tap closes
- [ ] Select tags → views filter; badge visible; 「全部」 clears badge
- [ ] No tags in DB → no filter icon
- [ ] Month filters the same way; switch tabs keeps selection
- [ ] Task with only attached (non-primary) tag appears when that tag is selected (week + month)

- [ ] **Step 6: Commit (only if user asked)**

```bash
git add lib/ui/shell/app_shell.dart
git commit -m "feat: move tag filter into AppBar menu for day/week/month"
```

---

## Spec coverage (self-review)

| Spec item | Task |
| --- | --- |
| Remove body chip row | Task 4 |
| Icon left of Settings | Task 4 |
| MenuAnchor / overlay multi-select | Task 4 |
| Badge when filter non-empty | Task 4 |
| Hide icon when no tags | Task 4 |
| Day/week/month share filter | Tasks 2–4 |
| Match primary ∪ attached | Tasks 1–3 |
| No persistence | (default state; no storage added) |
| Month layout on filtered list | Task 3 |
| Unify week match rule with day | Task 2 |
