# Inline Swatch Color Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In the settings drawer, create/edit color swatches via an inline picker (SV + hue + HEX) under the swatch row—no color `AlertDialog`.

**Architecture:** Extract a reusable `ArgbColorPickerPanel` widget from the existing dialog body in `argb_color_field.dart`. `showArgbColorPicker` becomes a thin `AlertDialog` wrapper around that panel (for any non-settings callers). `SettingsPage` holds edit mode state and inserts the panel below the swatch `Wrap`.

**Tech Stack:** Flutter/Dart, `flutter_test`, existing `ArgbColor` / `colorSwatchFromArgb` / `SettingsPage`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-inline-swatch-color-picker-design.md`
- Settings create/edit swatch: **no** `showArgbColorPicker` / color `AlertDialog`
- Inline panel sits under swatch `Wrap`, above Tags section
- Confirm → upsert then collapse; Cancel / re-tap same swatch → discard and collapse
- Long-press default/delete unchanged
- Do not change task-form or other `ArgbColorField` call sites this round
- Commit only when the user asks; mark logical commit boundaries in steps but do not run `git commit` unless requested

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/ui/common/argb_color_field.dart` | Extract `ArgbColorPickerPanel`; dialog wraps it |
| `test/ui/argb_color_picker_panel_test.dart` | Widget tests: HEX sync, confirm/cancel callbacks |
| `lib/ui/settings/settings_page.dart` | Inline expand state + wire create/edit |
| `test/ui/settings_swatch_inline_picker_test.dart` | Settings: tap opens panel, no dialog; cancel closes |

---

### Task 1: Extract `ArgbColorPickerPanel`

**Files:**
- Modify: `lib/ui/common/argb_color_field.dart`
- Create: `test/ui/argb_color_picker_panel_test.dart`

**Interfaces:**
- Produces:
```dart
class ArgbColorPickerPanel extends StatefulWidget {
  const ArgbColorPickerPanel({
    super.key,
    required this.initialArgb,
    required this.onConfirm,
    required this.onCancel,
    this.svSize = 240.0,
  });

  final int initialArgb;
  final ValueChanged<int> onConfirm;
  final VoidCallback onCancel;
  final double svSize;
}
```
- Consumes: `ArgbColor.parseHex` / `ArgbColor.toHex`
- Keeps: `Future<int?> showArgbColorPicker(...)` and `ArgbColorField` (dialog path still works)

- [ ] **Step 1: Write failing widget tests**

```dart
// test/ui/argb_color_picker_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/common/argb_color_field.dart';

void main() {
  testWidgets('confirm returns current argb; cancel does not', (tester) async {
    int? confirmed;
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () => cancelled = true,
            svSize: 120,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), '#FF0000');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(confirmed, 0xFFFF0000);

    confirmed = null;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () => cancelled = true,
            svSize: 120,
          ),
        ),
      ),
    );
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(cancelled, isTrue);
    expect(confirmed, isNull);
  });

  testWidgets('illegal hex does not change confirmed color path', (tester) async {
    int? confirmed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ArgbColorPickerPanel(
            initialArgb: 0xFF457BD9,
            onConfirm: (v) => confirmed = v,
            onCancel: () {},
            svSize: 120,
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pump();
    expect(confirmed, 0xFF457BD9);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/ui/argb_color_picker_panel_test.dart`

Expected: FAIL — `ArgbColorPickerPanel` not found / not a widget

- [ ] **Step 3: Implement panel + thin dialog wrapper**

In `lib/ui/common/argb_color_field.dart`:

1. Move `_ColorPickerDialogState` body (SV / hue / HEX / apply helpers) into public `ArgbColorPickerPanel` + `_ArgbColorPickerPanelState`.
2. Buttons call `widget.onConfirm(_argb)` / `widget.onCancel()` instead of `Navigator.pop`.
3. Use `widget.svSize` instead of hard-coded `240` (default `240`).
4. Rewrite `_ColorPickerDialog` to:

```dart
class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog({required this.initialArgb});
  final int initialArgb;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      content: ArgbColorPickerPanel(
        initialArgb: initialArgb,
        onConfirm: (argb) => Navigator.pop(context, argb),
        onCancel: () => Navigator.pop(context),
      ),
    );
  }
}
```

5. Keep `showArgbColorPicker` and `ArgbColorField` signatures unchanged.
6. Keep `_SvSquarePainter` as-is (private in same file).

- [ ] **Step 4: Run tests — expect PASS**

Run: `flutter test test/ui/argb_color_picker_panel_test.dart`

Expected: All tests passed

- [ ] **Step 5: Commit boundary (do not commit unless user asks)**

```bash
git add lib/ui/common/argb_color_field.dart test/ui/argb_color_picker_panel_test.dart
# git commit -m "refactor: extract ArgbColorPickerPanel from color dialog"
```

---

### Task 2: Settings inline expand / collapse

**Files:**
- Modify: `lib/ui/settings/settings_page.dart`
- Create: `test/ui/settings_swatch_inline_picker_test.dart`

**Interfaces:**
- Consumes: `ArgbColorPickerPanel` from Task 1
- Produces (private to settings):
```dart
/// null = collapsed; editingExisting = ColorSwatch; create = sentinel via separate flag
enum _SwatchEditorMode { closed, create, edit }

// State fields on _SettingsPageState:
_SwatchEditorMode _swatchEditor = _SwatchEditorMode.closed;
ColorSwatch? _editingSwatch; // set when mode == edit
Key _pickerKey = UniqueKey(); // bump when switching target so panel resets initialArgb
```

- [ ] **Step 1: Write failing settings widget tests**

Use a lightweight harness: pump `SettingsPage` only if the page needs heavy `AppServices`; if construction is heavy, extract a small private/testable `SwatchSection` **or** pump settings with mocked services.

Prefer the existing pattern in the repo. If no settings test harness exists, test a focused widget extracted in the same file / a thin `SwatchColorEditor` in `settings_page.dart` is OK **only if** wiring stays in SettingsPage.

Minimal acceptable test (if full SettingsPage is hard to pump): test a new package-visible helper widget:

```dart
// Prefer: full SettingsPage with fake services if already available.
// Fallback widget under test in settings_page.dart (not exported publicly beyond library):

class SwatchInlineEditorHost extends StatefulWidget {
  // For tests: list of swatches + callbacks; mirrors settings behavior.
}
```

**Preferred approach (match codebase):** inspect `test/ui/` for settings/fakes. If `AppServices` / task repo can be faked like other UI tests, pump `SettingsPage`. Otherwise implement `SwatchInlineHost` in `lib/ui/settings/swatch_inline_host.dart` used by SettingsPage and tested directly.

Concrete fallback API if needed:

```dart
// lib/ui/settings/swatch_inline_host.dart
class SwatchInlineHost extends StatefulWidget {
  const SwatchInlineHost({
    super.key,
    required this.swatches,
    required this.defaultArgb,
    required this.onUpsert,
  });
  final List<ColorSwatch> swatches;
  final int defaultArgb;
  final Future<void> Function(ColorSwatch swatch) onUpsert;
}
```

Write tests against that host:

```dart
// test/ui/settings_swatch_inline_picker_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/models/color_swatch.dart';
import 'package:ganttday/ui/settings/swatch_inline_host.dart';

ColorSwatch _s({
  required String id,
  required int argb,
  bool isDefault = false,
}) =>
    ColorSwatch(
      id: id,
      name: '',
      argb: argb,
      isDefault: isDefault,
      sortOrder: 0,
      slate: false,
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
          ),
        ),
      ),
    );

    expect(find.text('HEX'), findsNothing);
    await tester.tap(find.byType(InkWell).first);
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
          ),
        ),
      ),
    );
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsNothing);
    expect(upserts, 0);
  });

  testWidgets('re-tap same swatch collapses', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SwatchInlineHost(
            swatches: [_s(id: 'a', argb: 0xFF457BD9, isDefault: true)],
            defaultArgb: 0xFF457BD9,
            onUpsert: (_) async {},
          ),
        ),
      ),
    );
    final chip = find.byType(InkWell).first;
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsOneWidget);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('HEX'), findsNothing);
  });
}
```

Check `ColorSwatch` constructor fields in `lib/domain/models/color_swatch.dart` and adjust the factory in the test to match exactly.

- [ ] **Step 2: Run tests — expect FAIL**

Run: `flutter test test/ui/settings_swatch_inline_picker_test.dart`

Expected: FAIL — missing `SwatchInlineHost` (or SettingsPage behavior not present)

- [ ] **Step 3: Implement `SwatchInlineHost` + wire SettingsPage**

Create `lib/ui/settings/swatch_inline_host.dart` with:

- Header row: title 「色卡」 + 「新建」 `TextButton.icon` that opens create mode (`initialArgb: defaultArgb`)
- `Wrap` of chips (move `_SwatchChip` here from `settings_page.dart`, or keep chip in settings and pass builders — prefer moving chip into this file to keep one place)
- When open: `ArgbColorPickerPanel(key: _pickerKey, initialArgb: ..., onConfirm: ..., onCancel: close)`
- Tap chip id == editing id → close; else open edit with new key
- 「新建」 while create already open → close; else open create with new key
- `onConfirm`: build `ColorSwatch` via `colorSwatchFromArgb` (edit keeps id/name/sort/default/slate; create gets new UUID, `sortOrder: max+1`, `isDefault: false`) then `await onUpsert(swatch)` and close
- Editing chip: pass `isEditing: true` → use theme primary border (not the default red border); default red border still when `isDefault && !isEditing`

Then in `settings_page.dart` replace the 色卡 `Row` + `Wrap` block with:

```dart
SwatchInlineHost(
  swatches: sortedSwatches,
  defaultArgb: _defaultSwatch?.argb ?? 0xFF457BD9,
  onUpsert: (swatch) async {
    try {
      await widget.services.tasks.upsertSwatch(swatch);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '保存色卡失败：$e');
    }
  },
  onSetDefault: _setDefaultSwatch,
  onDelete: _deleteSwatch,
),
```

Add `onSetDefault` / `onDelete` to the host so long-press still works. Remove `_showSwatchDialog`. Remove unused `showArgbColorPicker` import from settings if nothing else uses it.

For drawer width: set panel `svSize` to something that fits (~`min(240, constraints)` via `LayoutBuilder`, e.g. `constraints.maxWidth.clamp(120, 240)`).

- [ ] **Step 4: Run tests — expect PASS**

Run:
```bash
flutter test test/ui/settings_swatch_inline_picker_test.dart test/ui/argb_color_picker_panel_test.dart
```

Expected: All tests passed

- [ ] **Step 5: Commit boundary (do not commit unless user asks)**

```bash
git add lib/ui/settings/swatch_inline_host.dart lib/ui/settings/settings_page.dart test/ui/settings_swatch_inline_picker_test.dart
# git commit -m "feat: inline swatch color picker under settings色卡 row"
```

---

### Task 3: Manual acceptance check

**Files:** none (verification only)

- [ ] **Step 1: Run focused + related tests**

```bash
flutter test test/ui/argb_color_picker_panel_test.dart test/ui/settings_swatch_inline_picker_test.dart test/domain/argb_color_test.dart
```

Expected: All tests passed

- [ ] **Step 2: Manual checklist (app run)**

1. Open Settings drawer → 色卡  
2. Tap a swatch → picker appears **under** chips, **no** modal  
3. Change HEX → 确定 → chip color updates, panel closes  
4. Tap swatch → 取消 → color unchanged, panel closes  
5. 「+ 新建」 → pick color → 确定 → new chip appears  
6. Long-press still offers 设为默认 / 删除  

- [ ] **Step 3: Commit boundary for whole feature (only if user asks)**

```bash
git add docs/superpowers/specs/2026-08-10-inline-swatch-color-picker-design.md docs/superpowers/plans/2026-08-10-inline-swatch-color-picker.md lib/ui/common/argb_color_field.dart lib/ui/settings/ test/ui/argb_color_picker_panel_test.dart test/ui/settings_swatch_inline_picker_test.dart
# git commit -m "feat: settings inline color picker for swatches"
```

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| No dialog for settings create/edit | Task 2 |
| Panel under swatch row | Task 2 layout |
| Create uses same panel | Task 2 create mode |
| Confirm upsert + collapse | Task 2 |
| Cancel / re-tap same → collapse no save | Task 2 + tests |
| Extract reusable panel; dialog thin wrap | Task 1 |
| Long-press unchanged | Task 2 host callbacks |
| Other `ArgbColorField` unchanged | Task 1 keeps API |

No TBD/placeholder steps. Types: `ArgbColorPickerPanel` / `SwatchInlineHost` names consistent across tasks.
