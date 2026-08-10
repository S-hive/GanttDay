# Swatch Delete In Picker Footer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the swatch long-press action sheet; show Delete on the left of the inline color-picker footer when editing a deletable swatch.

**Architecture:** Extend `ArgbColorPickerPanel` with an optional `onDelete`. When non-null, the footer is `删除 | Spacer | 取消 | 确定`. `SwatchInlineHost` drops long-press / bottom sheet and passes `onDelete` only for edit mode with `canDelete`. Existing `_deleteSwatch` confirmation stays in `SettingsPage`.

**Tech Stack:** Flutter/Dart, `flutter_test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-swatch-delete-in-picker-design.md`
- Remove long-press bottom sheet (`设为默认` / `删除` / `取消`); remove long-press gesture
- Delete button: picker footer **left**; Cancel/OK stay right
- Create mode: no Delete
- Only one swatch (`canDelete == false`): no Delete
- Set-as-default: no UI entry this round (red default border may remain)
- Delete confirmation / rebind: keep existing `SettingsPage._deleteSwatch`
- Dialog wrapper of the panel must not pass `onDelete` (unchanged)
- Commit only when the user asks; still mark logical commit boundaries per task

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/common/argb_color_field.dart` | Optional `onDelete` on `ArgbColorPickerPanel` footer |
| `test/ui/argb_color_picker_panel_test.dart` | Panel footer delete visibility + callback |
| `lib/ui/settings/swatch_inline_host.dart` | No long-press menu; wire `onDelete` when editing |
| `test/ui/settings_swatch_inline_picker_test.dart` | Host: edit shows delete; create/sole hide; no sheet |

---

### Task 1: Panel optional `onDelete` (TDD)

**Files:**
- Modify: `lib/ui/common/argb_color_field.dart` (`ArgbColorPickerPanel`)
- Modify: `test/ui/argb_color_picker_panel_test.dart`

**Interfaces:**
- Produces:
```dart
class ArgbColorPickerPanel extends StatefulWidget {
  const ArgbColorPickerPanel({
    super.key,
    required this.initialArgb,
    required this.onConfirm,
    required this.onCancel,
    this.onDelete, // NEW optional
    this.svSize = 240.0,
  });

  final VoidCallback? onDelete;
  // …existing fields…
}
```
- Consumes: none new

- [ ] **Step 1: Write failing tests**

Append to `test/ui/argb_color_picker_panel_test.dart`:

```dart
  testWidgets('omits delete when onDelete is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (_) {},
            onCancel: () {},
            svSize: 120,
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsNothing);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('shows delete on the left and invokes onDelete', (tester) async {
    var deleted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (_) {},
            onCancel: () {},
            onDelete: () => deleted = true,
            svSize: 120,
          ),
        ),
      ),
    );
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pump();
    expect(deleted, isTrue);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/argb_color_picker_panel_test.dart`

Expected: new tests FAIL (no `onDelete` / no `删除` when passed)

- [ ] **Step 3: Implement minimal panel API**

In `ArgbColorPickerPanel`:

1. Add `this.onDelete` to the constructor and `final VoidCallback? onDelete;`
2. Replace the footer `Row` with:

```dart
        Row(
          children: [
            if (widget.onDelete != null)
              TextButton(
                onPressed: widget.onDelete,
                child: const Text('删除'),
              ),
            const Spacer(),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => widget.onConfirm(_argb),
              child: const Text('确定'),
            ),
          ],
        ),
```

Leave `_ColorPickerDialog` unchanged (does not pass `onDelete`).

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/argb_color_picker_panel_test.dart`

Expected: All PASS (including existing confirm/cancel/hex tests)

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/ui/common/argb_color_field.dart test/ui/argb_color_picker_panel_test.dart
git commit -m "feat(ui): optional delete action on color picker footer"
```

---

### Task 2: Host — drop long-press sheet; wire delete

**Files:**
- Modify: `lib/ui/settings/swatch_inline_host.dart`
- Modify: `test/ui/settings_swatch_inline_picker_test.dart`

**Interfaces:**
- Consumes: `ArgbColorPickerPanel.onDelete` from Task 1
- Produces: edit+`canDelete` → panel `onDelete` calls `widget.onDelete(editingSwatch)`; no long-press sheet; create / sole swatch → no `onDelete`

- [ ] **Step 1: Write failing host tests**

Append to `test/ui/settings_swatch_inline_picker_test.dart`:

```dart
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
```

- [ ] **Step 2: Run host tests to verify new ones fail**

Run: `flutter test test/ui/settings_swatch_inline_picker_test.dart`

Expected: new tests FAIL (delete never shown / long-press still opens sheet)

- [ ] **Step 3: Update `SwatchInlineHost` / `_SwatchChip`**

1. When building `ArgbColorPickerPanel`, pass:

```dart
              return ArgbColorPickerPanel(
                key: _pickerKey,
                initialArgb: _initialArgb,
                svSize: svSize,
                onConfirm: _onConfirm,
                onCancel: _close,
                onDelete: (!_isCreateOpen &&
                        canDelete &&
                        _editingSwatch != null)
                    ? () => widget.onDelete(_editingSwatch!)
                    : null,
              );
```

2. Simplify `_SwatchChip`:
   - Remove `canDelete`, `onSetDefault`, `onDelete`, `_showActions`, `onLongPress`
   - Keep tap + visual borders
   - Tooltip: default → `'默认色卡'`；else → `'点击改色'`

3. Update call site in `build` accordingly (drop unused chip callbacks).

`onSetDefault` may remain on `SwatchInlineHost` constructor for now (Settings still passes it) even with no UI caller — do **not** remove the Settings wiring in this task unless the analyzer requires it; if unused-field warnings appear on the host field, keep the parameter (parent API) and suppress only if the project already does, otherwise leave as unused constructor param used by parent for future default UX. Prefer: keep `onSetDefault` on the host widget signature so `SettingsPage` need not change.

- [ ] **Step 4: Run tests**

Run:

```bash
flutter test test/ui/argb_color_picker_panel_test.dart test/ui/settings_swatch_inline_picker_test.dart
dart analyze lib/ui/common/argb_color_field.dart lib/ui/settings/swatch_inline_host.dart
```

Expected: all PASS; analyze clean (or only pre-existing unrelated warnings)

- [ ] **Step 5: Commit (only if user asked)**

```bash
git add lib/ui/settings/swatch_inline_host.dart test/ui/settings_swatch_inline_picker_test.dart
git commit -m "feat(settings): delete swatch from picker footer, drop long-press menu"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| Remove long-press sheet + gesture | Task 2 |
| Delete on picker footer left | Task 1 + 2 |
| Create: no delete | Task 2 |
| Sole swatch: no delete | Task 2 |
| No set-default entry | Task 2 |
| Keep existing delete confirm in Settings | Task 2 (calls `onDelete` only) |
| Dialog picker unchanged | Task 1 |
| Tooltip copy update | Task 2 |
