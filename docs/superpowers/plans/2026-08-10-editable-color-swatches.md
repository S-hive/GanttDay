# Editable Color Swatches Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users fully manage color swatches in Settings (CRUD + default), bind tasks/tags by swatch id, and migrate off stored hues.

**Architecture:** New `color_swatch` SQLite table is the source of truth. Tasks/tags store swatch ids. Factory 8 colors seed new/migrated DBs. UI picks from live swatch list; settings edit colors via hex + in-app color-picker dialog (Flutter desktop stand-in for OS picker; no Win32 FFI). Urgency still deepens from each swatch’s S/L.

**Tech Stack:** Flutter/Dart, sqflite, existing `TaskRepository` / backup JSON, `flutter_test` / `package:test`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-10-editable-color-swatches-design.md`
- At least 1 swatch; exactly one `is_default`
- Bind by id; never leave dangling refs on delete
- Color authority is opaque `argb`; H/S/L derived (or seeded) for urgency
- Backup format version **2**; import must accept v1 and migrate
- No drag-sort, no cloud sync, no urgency-curve change
- Do not invent Win32 `ChooseColor`; use dialog picker + hex
- Commit only when the user asks (repo convention); still prepare logical commit boundaries per task

---

## File map

| File | Responsibility |
| --- | --- |
| `lib/domain/models/color_swatch.dart` | `ColorSwatch` entity |
| `lib/domain/gantt/argb_color.dart` | hex parse/format + ARGB→HSL (no Flutter) |
| `lib/domain/gantt/factory_swatches.dart` | 8 factory seeds + `kDefaultSwatchId` |
| `lib/domain/gantt/swatch_resolve.dart` | resolve task→swatch id; farthest-swatch helper |
| `lib/domain/gantt/color_palette.dart` | shrink/delete: keep only if still needed as thin re-export during transition, then remove |
| `lib/domain/gantt/auto_hue.dart` | delete after callers use default swatch id |
| `lib/domain/models/task.dart` / `tag.dart` | swatch id fields |
| `lib/domain/gantt/urgency_palette.dart` | paint from resolved swatch H/S/L |
| `lib/platform/task_repository.dart` | swatch CRUD API |
| `lib/data/sqlite/app_database.dart` | schema v2 + `onUpgrade` 1→2 |
| `lib/data/sqlite/sqlite_task_repository.dart` | persist swatches + new task/tag columns |
| `lib/domain/backup/backup_document.dart` + `lib/data/backup/backup_service.dart` | v2 + v1 import path |
| `lib/ui/common/argb_color_field.dart` | hex + color-picker dialog |
| `lib/ui/common/swatch_picker.dart` | replace `hue_picker.dart` |
| `lib/ui/settings/settings_page.dart` | swatch list CRUD |
| `lib/ui/task/task_form_page.dart`, day/week/month, `app_shell.dart` | consume swatch ids |
| tests under `test/domain/`, `test/data/` | TDD for helpers, migration, backup |

---

### Task 1: ARGB helpers + factory seeds (TDD)

**Files:**
- Create: `lib/domain/gantt/argb_color.dart`
- Create: `lib/domain/models/color_swatch.dart`
- Create: `lib/domain/gantt/factory_swatches.dart`
- Create: `test/domain/argb_color_test.dart`
- Create: `test/domain/factory_swatches_test.dart`

**Interfaces:**
- Produces: `ArgbColor.parseHex`, `ArgbColor.toHex`, `ArgbColor.toHsl`, `ColorSwatch`, `kFactoryColorSwatches`, `kDefaultSwatchId`

- [ ] **Step 1: Write failing tests**

```dart
// test/domain/argb_color_test.dart
import 'package:ganttday/domain/gantt/argb_color.dart';
import 'package:test/test.dart';

void main() {
  test('parseHex accepts #RGB and #RRGGBB', () {
    expect(ArgbColor.parseHex('#abc'), 0xFFAABBCC);
    expect(ArgbColor.parseHex('#AABBCC'), 0xFFAABBCC);
    expect(ArgbColor.parseHex('ffdac1'), 0xFFFFDAC1);
    expect(ArgbColor.parseHex('nope'), isNull);
  });

  test('toHex formats #RRGGBB uppercase', () {
    expect(ArgbColor.toHex(0xFFFFDAC1), '#FFDAC1');
  });

  test('toHsl matches known azure approx', () {
    final hsl = ArgbColor.toHsl(0xFF457BD9);
    expect(hsl.hue, closeTo(218, 2));
    expect(hsl.saturation, greaterThan(0.5));
    expect(hsl.lightness, closeTo(0.56, 0.05));
  });
}
```

```dart
// test/domain/factory_swatches_test.dart
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:test/test.dart';

void main() {
  test('eight factory swatches; azure default', () {
    expect(kFactoryColorSwatches, hasLength(8));
    expect(kDefaultSwatchId, 'azure');
    expect(
      kFactoryColorSwatches.singleWhere((s) => s.isDefault).id,
      'azure',
    );
    expect(
      [for (final s in kFactoryColorSwatches) s.argb],
      [
        0xFF457BD9,
        0xFFFFDAC1,
        0xFFE2F0CB,
        0xFFB5EAD7,
        0xFFDDD6FE,
        0xFFBAE6FD,
        0xFFFEF3C7,
        0xFFDEE2E6,
      ],
    );
    expect(kFactoryColorSwatches.singleWhere((s) => s.id == 'gray').slate, isTrue);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `dart test test/domain/argb_color_test.dart test/domain/factory_swatches_test.dart`  
Expected: FAIL (missing libraries)

- [ ] **Step 3: Implement**

```dart
// lib/domain/gantt/argb_color.dart
import 'dart:math' as math;

class ArgbHsl {
  const ArgbHsl({
    required this.hue,
    required this.saturation,
    required this.lightness,
  });
  final double hue; // 0..360
  final double saturation; // 0..1
  final double lightness; // 0..1
}

class ArgbColor {
  ArgbColor._();

  static int? parseHex(String raw) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return 0xFF000000 | v;
  }

  static String toHex(int argb) {
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Standard HSL from sRGB (same convention as Flutter HSLColor).
  static ArgbHsl toHsl(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final l = (max + min) / 2;
    if (max == min) {
      return ArgbHsl(hue: 0, saturation: 0, lightness: l);
    }
    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    double h;
    if (max == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (max == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
    return ArgbHsl(hue: h * 360, saturation: s, lightness: l);
  }
}
```

```dart
// lib/domain/models/color_swatch.dart
class ColorSwatch {
  const ColorSwatch({
    required this.id,
    required this.name,
    required this.argb,
    required this.hue,
    required this.saturation,
    required this.lightness,
    required this.sortOrder,
    this.isDefault = false,
    this.slate = false,
  });

  final String id;
  final String name;
  final int argb;
  final int hue;
  final double saturation;
  final double lightness;
  final int sortOrder;
  final bool isDefault;
  final bool slate;

  ColorSwatch copyWith({
    String? name,
    int? argb,
    int? hue,
    double? saturation,
    double? lightness,
    int? sortOrder,
    bool? isDefault,
    bool? slate,
  }) {
    return ColorSwatch(
      id: id,
      name: name ?? this.name,
      argb: argb ?? this.argb,
      hue: hue ?? this.hue,
      saturation: saturation ?? this.saturation,
      lightness: lightness ?? this.lightness,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      slate: slate ?? this.slate,
    );
  }
}
```

```dart
// lib/domain/gantt/factory_swatches.dart
import '../models/color_swatch.dart';

const String kDefaultSwatchId = 'azure';

/// Seed rows for new DBs and schema 1→2 migration. H/S/L match prior palette.
const List<ColorSwatch> kFactoryColorSwatches = [
  ColorSwatch(
    id: 'azure',
    name: '霁蓝',
    argb: 0xFF457BD9,
    hue: 218,
    saturation: 0.661,
    lightness: 0.561,
    sortOrder: 0,
    isDefault: true,
  ),
  ColorSwatch(
    id: 'peach',
    name: '桃',
    argb: 0xFFFFDAC1,
    hue: 24,
    saturation: 1.0,
    lightness: 0.878,
    sortOrder: 1,
  ),
  ColorSwatch(
    id: 'leaf',
    name: '芽绿',
    argb: 0xFFE2F0CB,
    hue: 83,
    saturation: 0.551,
    lightness: 0.869,
    sortOrder: 2,
  ),
  ColorSwatch(
    id: 'mint',
    name: '薄荷',
    argb: 0xFFB5EAD7,
    hue: 158,
    saturation: 0.559,
    lightness: 0.814,
    sortOrder: 3,
  ),
  ColorSwatch(
    id: 'lavender',
    name: '淡紫',
    argb: 0xFFDDD6FE,
    hue: 251,
    saturation: 0.951,
    lightness: 0.918,
    sortOrder: 4,
  ),
  ColorSwatch(
    id: 'sky',
    name: '天空',
    argb: 0xFFBAE6FD,
    hue: 201,
    saturation: 0.943,
    lightness: 0.861,
    sortOrder: 5,
  ),
  ColorSwatch(
    id: 'cream',
    name: '奶油',
    argb: 0xFFFEF3C7,
    hue: 48,
    saturation: 0.964,
    lightness: 0.888,
    sortOrder: 6,
  ),
  ColorSwatch(
    id: 'gray',
    name: '灰',
    argb: 0xFFDEE2E6,
    hue: 211,
    saturation: 0.137,
    lightness: 0.886,
    sortOrder: 7,
    slate: true,
  ),
];
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `dart test test/domain/argb_color_test.dart test/domain/factory_swatches_test.dart`

- [ ] **Step 5: Commit boundary** — `feat(domain): add ColorSwatch seeds and ARGB helpers`

---

### Task 2: Resolve helpers + Task/Tag model field rename (TDD)

**Files:**
- Create: `lib/domain/gantt/swatch_resolve.dart`
- Create: `test/domain/swatch_resolve_test.dart`
- Modify: `lib/domain/models/task.dart`
- Modify: `lib/domain/models/tag.dart`

**Interfaces:**
- Consumes: `ColorSwatch`, `Task`, `Tag`
- Produces: `resolveTaskSwatchId`, `farthestSwatchId`, `ColorSwatch.withArgb(...)`

- [ ] **Step 1: Update models**

Replace hue fields:

```dart
// Tag
class Tag {
  const Tag({required this.id, required this.name, required this.swatchId});
  final String id;
  final String name;
  final String swatchId;
}

// Task — replace autoHue/overrideHue with:
required this.autoSwatchId,
this.overrideSwatchId,
// fields:
final String autoSwatchId;
final String? overrideSwatchId;
// copyWith: clearOverrideSwatch instead of clearOverrideHue
```

Fix all compile breaks in later tasks; for this task, update call sites that block analysis only if needed — prefer fixing in Tasks 4–9. If `dart analyze` floods, do a mechanical rename pass in the same commit as models.

Helper on swatch construction from argb:

```dart
// in swatch_resolve.dart or color_swatch.dart
ColorSwatch colorSwatchFromArgb({
  required String id,
  required String name,
  required int argb,
  required int sortOrder,
  bool isDefault = false,
  bool slate = false,
}) {
  final hsl = ArgbColor.toHsl(argb);
  return ColorSwatch(
    id: id,
    name: name,
    argb: argb,
    hue: hsl.hue.round() % 360,
    saturation: hsl.saturation,
    lightness: hsl.lightness,
    sortOrder: sortOrder,
    isDefault: isDefault,
    slate: slate,
  );
}
```

```dart
String resolveTaskSwatchId(Task task, Map<String, Tag> tagsById) {
  final override = task.overrideSwatchId;
  if (override != null) return override;
  final tagId = task.primaryTagId;
  if (tagId != null) {
    final tag = tagsById[tagId];
    if (tag != null) return tag.swatchId;
  }
  return task.autoSwatchId;
}

String farthestSwatchId(
  List<ColorSwatch> palette,
  List<int> existingHues,
) {
  if (palette.isEmpty) {
    throw StateError('palette empty');
  }
  if (existingHues.isEmpty) {
    return palette.firstWhere((s) => s.isDefault, orElse: () => palette.first).id;
  }
  var bestId = palette.first.id;
  var bestScore = -1;
  for (final swatch in palette) {
    var minDist = 360;
    for (final h in existingHues) {
      final direct = (swatch.hue - h).abs() % 360;
      final d = direct > 180 ? 360 - direct : direct;
      if (d < minDist) minDist = d;
    }
    if (minDist > bestScore) {
      bestScore = minDist;
      bestId = swatch.id;
    }
  }
  return bestId;
}
```

- [ ] **Step 2: Tests for resolve + farthest**

```dart
test('resolve prefers override then tag then auto', () {
  final tags = {
    'tg': const Tag(id: 'tg', name: 't', swatchId: 'peach'),
  };
  final task = Task(
    id: '1',
    title: 'x',
    plannedStart: 0,
    plannedEnd: 1,
    autoSwatchId: 'azure',
    primaryTagId: 'tg',
    overrideSwatchId: 'mint',
    createdAt: 0,
  );
  expect(resolveTaskSwatchId(task, tags), 'mint');
  expect(
    resolveTaskSwatchId(
      task.copyWith(clearOverrideSwatch: true),
      tags,
    ),
    'peach',
  );
});
```

- [ ] **Step 3: Run** `dart test test/domain/swatch_resolve_test.dart` — PASS

- [ ] **Step 4: Commit boundary** — `refactor(domain): bind tasks/tags to swatch ids`

---

### Task 3: Schema v2 + migration (TDD)

**Files:**
- Modify: `lib/data/sqlite/app_database.dart`
- Create: `lib/data/sqlite/swatch_migration.dart` (pure SQL helpers callable from upgrade)
- Create: `test/data/schema_v2_migration_test.dart`

**Interfaces:**
- Consumes: `kFactoryColorSwatches`
- Produces: `schemaVersion = 2`, `applySchema` creates v2 tables, `migrateV1toV2(DatabaseExecutor)`

- [ ] **Step 1: Failing migration test**

Open in-memory DB, manually create **v1** schema (copy current `applySchema` SQL), insert:

- tag hue `24` (peach)
- tag hue `999` (custom → new swatch)
- task `auto_hue: 218`, `override_hue: null`, primary tag peach
- task `auto_hue: 333` (orphan custom)

Call `AppDatabase.open` / upgrade path OR call `migrateV1toV2` then assert:

- 8 factory + ≥1 custom swatches
- tags/tasks have swatch ids; peach tag → `peach`
- custom hues got distinct swatch rows
- no `auto_hue` column

- [ ] **Step 2: Implement schema**

`applySchema` for fresh DBs must create:

```sql
CREATE TABLE color_swatch (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  argb INTEGER NOT NULL,
  hue INTEGER NOT NULL,
  saturation REAL NOT NULL,
  lightness REAL NOT NULL,
  is_default INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  slate INTEGER NOT NULL DEFAULT 0
);
-- task: auto_swatch_id TEXT NOT NULL, override_swatch_id TEXT
-- tag: swatch_id TEXT NOT NULL
```

Seed factory swatches in `onCreate` after tables.

`OpenDatabaseOptions(version: 2, onCreate: ..., onUpgrade: (db, old, neu) async { if (old < 2) await migrateV1toV2(db); })`

`migrateV1toV2` outline:

1. `CREATE TABLE color_swatch (...)`
2. Insert factory rows
3. `ALTER TABLE tag ADD COLUMN swatch_id TEXT;`
4. For each tag: match hue → factory id else insert `colorSwatchFromArgb(id: uuid, name: '自定义色', ...)` and set `swatch_id`
5. Same for tasks → `auto_swatch_id` / `override_swatch_id`
6. Rebuild `tag`/`task` without hue columns (SQLite: create new, copy, drop, rename) — follow existing project style if any; otherwise standard table-rebuild

- [ ] **Step 3: Tests PASS**

Run: `dart test test/data/schema_v2_migration_test.dart`

- [ ] **Step 4: Commit boundary** — `feat(db): schema v2 color_swatch and hue→id migration`

---

### Task 4: Repository swatch CRUD + task/tag persistence

**Files:**
- Modify: `lib/platform/task_repository.dart`
- Modify: `lib/data/sqlite/sqlite_task_repository.dart`
- Modify: `test/data/sqlite_task_repository_test.dart` (and any fixtures using hues)

**Interfaces:**
- Produces on `TaskRepository`:

```dart
Future<List<ColorSwatch>> listSwatches();
Stream<List<ColorSwatch>> watchSwatches(); // or notify via existing change bus + list
Future<ColorSwatch> defaultSwatch();
Future<void> upsertSwatch(ColorSwatch swatch);
Future<void> setDefaultSwatch(String id);
/// Rebinds task.auto/override and tag.swatch_id from [id] → [rebindToId], then deletes.
/// Throws if only one swatch remains or [rebindToId] == [id] / missing.
Future<void> deleteSwatch(String id, {required String rebindToId});
```

- [ ] **Step 1: Tests**

```dart
test('cannot delete last swatch', () async {
  // fresh DB has 8; delete down to 1 then expect throw
});

test('deleteSwatch rebinds tasks and tags', () async {
  await repo.upsertTag(Tag(id: 'tg', name: 'a', swatchId: 'peach'));
  await repo.upsert(Task(..., autoSwatchId: 'peach', ...));
  await repo.deleteSwatch('peach', rebindToId: 'azure');
  expect((await repo.listTags()).single.swatchId, 'azure');
  expect((await repo.getById(...))!.autoSwatchId, 'azure');
  expect(await repo.listSwatches(), isNot(contains(predicate((s) => s.id == 'peach'))));
});

test('setDefaultSwatch clears previous default', () async {
  await repo.setDefaultSwatch('mint');
  final all = await repo.listSwatches();
  expect(all.where((s) => s.isDefault).map((s) => s.id), ['mint']);
});
```

- [ ] **Step 2: Implement** — upsert clears other defaults when `isDefault`; `deleteSwatch` transaction: UPDATE refs, DELETE row, ensure ≥1 left and exactly one default (if deleted was default, set `rebindToId` as default)

- [ ] **Step 3: Fix repository tests + seed helpers to use swatch ids**

- [ ] **Step 4: Commit boundary** — `feat(data): swatch CRUD on TaskRepository`

---

### Task 5: UrgencyPalette from ColorSwatch

**Files:**
- Modify: `lib/domain/gantt/urgency_palette.dart`
- Modify: `test/domain/urgency_palette_test.dart`

**Interfaces:**
- Change `paint({required int baseHue, ...})` → `paint({required ColorSwatch base, ...})`
- Use `base.hue`, `base.saturation`, `base.lightness` instead of `swatchForHue`

- [ ] **Step 1: Update tests to pass a factory swatch**
- [ ] **Step 2: Implement**
- [ ] **Step 3: `dart test test/domain/urgency_palette_test.dart` PASS
- [ ] **Step 4: Commit boundary** — `refactor(domain): urgency paint from ColorSwatch`

---

### Task 6: Backup format v2 + v1 import

**Files:**
- Modify: `lib/domain/backup/backup_document.dart`
- Modify: `lib/data/backup/backup_service.dart`
- Modify: `test/data/backup_service_test.dart`

**Interfaces:**
- `supportedVersion = 2`
- Export includes `color_swatches: [{id,name,argb,hue,saturation,lightness,is_default,sort_order,slate}]`
- Tasks: `auto_swatch_id`, `override_swatch_id`; tags: `swatch_id`
- Import v2: validate swatch ids exist / create from payload first
- Import v1: if `version == 1`, run in-memory hue→swatch mapping (same rules as DB migration), then write v2 rows

- [ ] **Step 1: Update round-trip test for v2 fields**
- [ ] **Step 2: Add test importing a minimal v1 JSON string → swatches + rebound ids**
- [ ] **Step 3: Implement**
- [ ] **Step 4: PASS `dart test test/data/backup_service_test.dart`**
- [ ] **Step 5: Commit boundary** — `feat(backup): version 2 with color_swatches`

---

### Task 7: `ArgbColorField` + `SwatchPicker` UI

**Files:**
- Create: `lib/ui/common/argb_color_field.dart`
- Create: `lib/ui/common/swatch_picker.dart`
- Delete (after switch): `lib/ui/common/hue_picker.dart`

**Interfaces:**
- `ArgbColorField({required int argb, required ValueChanged<int> onChanged})`
- `SwatchPicker({required List<ColorSwatch> swatches, required String swatchId, required ValueChanged<String> onChanged})`

- [ ] **Step 1: Implement `ArgbColorField`**

Layout: `Row` with tappable `Container` color chip + `TextField` for hex.

On chip tap → `showDialog` with:
- large preview
- hue slider 0–360
- saturation / lightness sliders **or** a simple `HSVColor` sat-val `GestureDetector` box
- OK / Cancel

On hex change: if `ArgbColor.parseHex` returns non-null, call `onChanged` and sync chip; if null, keep last valid preview (do not call `onChanged`).

When dialog confirms a `Color`, convert via `color.value` (ARGB) → `onChanged`.

> Note: This is the Flutter stand-in for “系统取色器”; do not add FFI.

- [ ] **Step 2: Implement `SwatchPicker`**

`Wrap` of circular swatches from `swatches` (sorted by `sortOrder`); selecting calls `onChanged(id)`. No custom hue slider.

- [ ] **Step 3: Manual smoke later in Task 9; no widget test required unless easy**

- [ ] **Step 4: Commit boundary** — `feat(ui): ArgbColorField and SwatchPicker`

---

### Task 8: Settings page swatch management

**Files:**
- Modify: `lib/ui/settings/settings_page.dart`

- [ ] **Step 1: Load `listSwatches()` alongside tags**
- [ ] **Step 2: UI section「色卡」**

ListTile per swatch:
- leading: `CircleAvatar(backgroundColor: Color(s.argb))`
- title: name
- trailing: star (`Icons.star` / `star_border`) → `setDefaultSwatch`
- edit icon → dialog: name `TextField` + `ArgbColorField` → `upsertSwatch` with H/S/L from `ArgbColor.toHsl`
- delete: disabled if `swatches.length == 1`; else dialog:
  - if refs exist OR always: dropdown of other swatches for rebind; option “当前默认” preselects default id (if deleting default, require choosing another as both rebind and new default — call `setDefaultSwatch(rebindToId)` then `deleteSwatch`)
  - confirm → `deleteSwatch(id, rebindToId: ...)`

「新建」button → same dialog with new UUID id, `sortOrder: max+1`, `isDefault: false`.

- [ ] **Step 3: Tag create dialog uses `SwatchPicker` + `farthestSwatchId`**

- [ ] **Step 4: Manual check list in Task 10**

- [ ] **Step 5: Commit boundary** — `feat(settings): manage color swatches`

---

### Task 9: Wire day / week / month / task form / shell

**Files:**
- Modify: `lib/ui/day/day_gantt_page.dart`
- Modify: `lib/ui/week/week_gantt_page.dart`
- Modify: `lib/ui/month/month_page.dart`
- Modify: `lib/ui/task/task_form_page.dart`
- Modify: `lib/ui/shell/app_shell.dart`
- Modify: `tools/seed_from_ex.dart` if still used
- Remove: `lib/domain/gantt/auto_hue.dart`, obsolete APIs in `color_palette.dart`
- Update: remaining tests that construct `Task`/`Tag` with hues

**Resolve pattern (all views):**

```dart
final swatches = {for (final s in await repo.listSwatches()) s.id: s};
// or keep in State from watch
final id = resolveTaskSwatchId(task, tagsById);
final base = swatches[id] ?? swatches[kDefaultSwatchId]!;
final paint = UrgencyPalette.paint(base: base, ...);
// month/week static color: Color(base.argb) or BarPaint from base S/L
```

- [ ] **Step 1: Day page** — create task with `autoSwatchId: (await defaultSwatch()).id`; paint via resolve
- [ ] **Step 2: Week + month** — same resolve; drop `swatchForHue`
- [ ] **Step 3: Task form** — override toggle stores `overrideSwatchId`; `SwatchPicker`; tag chips use `Color(swatches[tag.swatchId]!.argb)`
- [ ] **Step 4: App shell tag filter colors from swatch map
- [ ] **Step 5: Delete `HuePicker` / `auto_hue.dart` / unused `kTaskColorPalette` helpers; rewrite `test/domain/color_palette_test.dart` → factory/resolve tests only
- [ ] **Step 6: `dart test` full suite PASS
- [ ] **Step 7: Commit boundary** — `feat(ui): paint and forms use swatch ids`

---

### Task 10: Verification checklist

- [ ] **Step 1: Automated**

Run: `dart test`  
Expected: all PASS

- [ ] **Step 2: Manual (Windows)**

1. Fresh install / empty DB → 8 swatches, azure default, new task is 霁蓝  
2. Settings: rename + recolor peach via hex `#FF0000` → existing peach-tagged bars update  
3. System-picker dialog + hex stay in sync  
4. Set mint default → new tasks mint  
5. Delete a used swatch → rebind dialog → no crash; bars show rebind color  
6. Cannot delete last swatch  
7. Export backup → wipe → import → swatches + bindings restored  
8. (If available) import old v1 backup → migrates  

- [ ] **Step 3: Commit only if user requests**

---

## Spec coverage (self-review)

| Spec requirement | Task |
| --- | --- |
| Full CRUD in settings | 8 |
| Id binding | 2, 4, 9 |
| System picker + hex | 7 (dialog + hex) |
| ≥1 swatch; editable default star | 4, 8 |
| Table + migration | 3 |
| Backup v2 / v1 import | 6 |
| SwatchPicker; no custom hue slider | 7, 8, 9 |
| New task = default swatch | 9 |
| Tag farthest suggestion | 8 (`farthestSwatchId`) |
| Delete rebind | 4, 8 |
| Urgency from S/L unchanged curve | 5 |
| Non-goals (no drag/cloud/curve) | respected |

**Placeholder scan:** none intentional.  
**Type consistency:** `ColorSwatch`, `autoSwatchId` / `overrideSwatchId` / `swatchId` used throughout.
