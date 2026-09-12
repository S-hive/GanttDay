# Side Drawer Form/Settings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Open task edit and settings as a right-side blurred drawer instead of a full-screen route.

**Architecture:** Shared `showSideDrawer` (`showGeneralDialog` + `BackdropFilter` barrier + right `SlideTransition` panel). `AppShell` opens drawers; `TaskFormPage` / `SettingsPage` become drawer-friendly content (header + scroll body + footer actions). Barrier tap pops without saving task edits; settings stay immediate-write.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `TaskFormPage` / `SettingsPage` / `AppShell`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-side-drawer-form-settings-design.md`
- Width ≈ 40% of screen, clamp ~360–480
- Backdrop: blur + translucent scrim; tap scrim closes
- Task: scrim/back = discard; 「保存」 success = persist then close
- Settings: still immediate write; scrim / 「完成」 / back = close only
- Do not change drag-create 「新任务」 popup
- Nested settings dialogs stay as `showDialog` on top of the drawer
- Commit only when the user asks (repo convention); mark logical commit boundaries

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/common/side_drawer.dart` | `showSideDrawer` + panel chrome |
| `test/ui/side_drawer_test.dart` | Barrier dismiss + panel present |
| `lib/ui/task/task_form_page.dart` | Drawer layout; save/delete still `pop` |
| `lib/ui/settings/settings_page.dart` | Drawer layout + 「完成」 |
| `lib/ui/shell/app_shell.dart` | `_openForm` / `_openSettings` use drawer |

---

### Task 1: `showSideDrawer` helper (TDD)

**Files:**
- Create: `lib/ui/common/side_drawer.dart`
- Create: `test/ui/side_drawer_test.dart`

**Interfaces:**
- Produces:
```dart
Future<T?> showSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
})
```
- Consumes: Flutter `showGeneralDialog`

- [ ] **Step 1: Write failing widget tests**

```dart
// test/ui/side_drawer_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/side_drawer.dart';

void main() {
  testWidgets('opens panel from the right with drawer content', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showSideDrawer<void>(
                  context: context,
                  builder: (_) => const Text('drawer-body'),
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
    expect(find.text('drawer-body'), findsOneWidget);
  });

  testWidgets('tapping barrier closes drawer', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                showSideDrawer<void>(
                  context: context,
                  builder: (_) => const SizedBox(
                    width: 200,
                    child: Text('drawer-body'),
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
    expect(find.text('drawer-body'), findsOneWidget);

    // Tap left side (scrim), not the drawer panel.
    await tester.tapAt(const Offset(20, 300));
    await tester.pumpAndSettle();
    expect(find.text('drawer-body'), findsNothing);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/ui/side_drawer_test.dart`
Expected: FAIL (missing `side_drawer.dart`)

- [ ] **Step 3: Implement `showSideDrawer`**

```dart
// lib/ui/common/side_drawer.dart
import 'dart:ui';

import 'package:flutter/material.dart';

const double kSideDrawerMinWidth = 360;
const double kSideDrawerMaxWidth = 480;
const double kSideDrawerWidthFraction = 0.4;

double sideDrawerWidthFor(double screenWidth) =>
    (screenWidth * kSideDrawerWidthFraction)
        .clamp(kSideDrawerMinWidth, kSideDrawerMaxWidth);

Future<T?> showSideDrawer<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final width = sideDrawerWidthFor(MediaQuery.sizeOf(ctx).width);
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Theme.of(ctx).colorScheme.surface,
          elevation: 8,
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: width,
            height: double.infinity,
            child: builder(ctx),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            behavior: HitTestBehavior.opaque,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: FadeTransition(
                opacity: curved,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            ),
          ),
          SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ],
      );
    },
  );
}
```

Notes:
- Do **not** put a second barrier that blocks nested `showDialog` from settings; nested dialogs use the root navigator by default and should still work.
- If barrier tap and `barrierDismissible` double-pop, keep **one** dismiss path: prefer the explicit `GestureDetector` on the blur and set `barrierDismissible: false`, **or** rely on `barrierDismissible` only and make the blur non-tappable. Choose **one** in implementation; tests must still pass.
- Recommended: `barrierDismissible: true` with transparent system barrier **and** visual blur in `transitionBuilder` that does **not** call `pop` itself (system barrier handles tap). Then remove the inner `GestureDetector` `onTap` to avoid double-pop.

Adjusted recommended `transitionBuilder` (system barrier dismisses):

```dart
transitionBuilder: (ctx, animation, secondaryAnimation, child) {
  final curved = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  return Stack(
    fit: StackFit.expand,
    children: [
      IgnorePointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: FadeTransition(
            opacity: curved,
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.25),
            ),
          ),
        ),
      ),
      SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    ],
  );
},
```

With `barrierDismissible: true` and `barrierColor: Colors.black26` **or** transparent + IgnorePointer blur as above. If transparent barrier does not receive taps under `IgnorePointer` blur, use `barrierColor: Colors.black.withValues(alpha: 0.01)` so hits register, and still paint the blur visually.

- [ ] **Step 4: Run tests — expect PASS**

Run: `flutter test test/ui/side_drawer_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/ui/common/side_drawer.dart test/ui/side_drawer_test.dart
git commit -m "feat: add blurred right side drawer helper"
```

---

### Task 2: Adapt `TaskFormPage` for drawer chrome

**Files:**
- Modify: `lib/ui/task/task_form_page.dart`

**Interfaces:**
- Consumes: opened inside `showSideDrawer` (context can `Navigator.pop`)
- Produces: same save/delete/complete behavior; no full-screen AppBar back affordance required (scrim closes)

- [ ] **Step 1: Replace `Scaffold`/`AppBar` with drawer column**

Change `build` to:

```dart
@override
Widget build(BuildContext context) {
  final theme = Theme.of(context);
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _isEdit ? '编辑任务' : '新建任务',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_isEdit)
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '',
                onPressed: _saving ? null : _delete,
              ),
          ],
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // ... keep existing form fields unchanged ...
          ],
        ),
      ),
      const Divider(height: 1),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_error != null) ...[
                Text(_error!,
                    style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 8),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
              // keep complete / uncomplete buttons as today under 保存
            ],
          ),
        ),
      ),
    ],
  );
}
```

Move `_error` display and primary actions into the footer if they were only at the bottom of the `ListView` — avoid duplicating the error Text.

- [ ] **Step 2: Keep `_save` / `_delete` / `_markComplete` / `_uncomplete` using `Navigator.of(context).pop(...)`** — already correct for dialog routes.

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/ui/task/task_form_page.dart`
Expected: No issues

- [ ] **Step 4: Commit (only if user asked)**

```bash
git add lib/ui/task/task_form_page.dart
git commit -m "feat: layout task form for side drawer"
```

---

### Task 3: Adapt `SettingsPage` for drawer + 「完成」

**Files:**
- Modify: `lib/ui/settings/settings_page.dart`

**Interfaces:**
- Consumes: `showSideDrawer`
- Produces: 「完成」 calls `Navigator.pop(context)`; settings writes unchanged

- [ ] **Step 1: Replace Scaffold/AppBar with drawer column**

```dart
return Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Text(
        '设置',
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    const Divider(height: 1),
    Expanded(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // existing settings body (可视时段, 紧迫窗口, 色卡, 标签, 备份...)
        ],
      ),
    ),
    const Divider(height: 1),
    SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ),
    ),
  ],
);
```

- [ ] **Step 2: Leave nested `showDialog` / `showArgbColorPicker` as-is**

- [ ] **Step 3: Analyze**

Run: `dart analyze lib/ui/settings/settings_page.dart`
Expected: No issues

- [ ] **Step 4: Commit (only if user asked)**

```bash
git add lib/ui/settings/settings_page.dart
git commit -m "feat: layout settings for side drawer with done button"
```

---

### Task 4: Wire `AppShell` to drawers

**Files:**
- Modify: `lib/ui/shell/app_shell.dart`

**Interfaces:**
- Consumes: `showSideDrawer` from Task 1; adapted pages from Tasks 2–3

- [ ] **Step 1: Import and replace `_openForm` / `_openSettings`**

```dart
import '../common/side_drawer.dart';

Future<void> _openForm({Task? existing}) async {
  await showSideDrawer<void>(
    context: context,
    builder: (_) => TaskFormPage(
      services: widget.services,
      existing: existing,
      initialStart: existing == null
          ? WallClock.minutes(
              DateTime(_date.year, _date.month, _date.day, 9))
          : null,
      initialEnd: existing == null
          ? WallClock.minutes(
              DateTime(_date.year, _date.month, _date.day, 10))
          : null,
    ),
  );
  await _reloadTags();
}

Future<void> _openSettings() async {
  await showSideDrawer<void>(
    context: context,
    builder: (_) => SettingsPage(services: widget.services),
  );
  await _reloadTags();
}
```

Remove `MaterialPageRoute` / `Navigator.push` for these two.

- [ ] **Step 2: Analyze shell**

Run: `dart analyze lib/ui/shell/app_shell.dart lib/ui/common/side_drawer.dart`
Expected: No issues

- [ ] **Step 3: Manual acceptance**

- [ ] Day bar tap → right drawer, blur behind
- [ ] Scrim tap → closes; task edits discarded if not saved
- [ ] 「保存」 success → closes; bar updates
- [ ] Settings gear → drawer; change hour/swatch applies immediately
- [ ] Settings 「完成」 or scrim → closes
- [ ] Settings nested delete/color dialogs still work
- [ ] Drag-create 「新任务」 popup unchanged

- [ ] **Step 4: Commit (only if user asked)**

```bash
git add lib/ui/shell/app_shell.dart
git commit -m "feat: open task form and settings in side drawer"
```

---

## Spec coverage (self-review)

| Spec item | Task |
| --- | --- |
| Right slide + blur | Task 1 |
| Width 40% clamp 360–480 | Task 1 |
| Task discard on scrim | Tasks 1, 2, 4 |
| Task save then close | Task 2 |
| Settings immediate write + 完成 | Task 3 |
| Wire shell | Task 4 |
| Nested dialogs unchanged | Task 3 note |
| Drag-create popup out of scope | Task 4 checklist |
