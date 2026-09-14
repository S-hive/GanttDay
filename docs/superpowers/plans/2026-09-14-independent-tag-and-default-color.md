# Independent Tag and Default Color Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split tags and default colors into independent tables, give each task at most one tag, paint with override ARGB → tag ARGB → current default → `#457BD9`, and show every color chip as a 60×30 sharp rectangle.

**Architecture:** Domain owns `Tag` (name+argb), `DefaultColor` (argb+isCurrent), and `resolveTaskArgb`. SQLite schema 3 drops `color_swatch` / `task_tag` / swatch FKs. UI settings and task form use a shared `RectSwatch` (60×30, radius 0). Theme seed follows current default color only.

**Tech Stack:** Flutter/Dart, sqflite, `package:test` / `flutter_test`. Spec: `docs/superpowers/specs/2026-09-14-independent-tag-and-default-color-design.md`.

## Global Constraints

- Color chips everywhere: `60×30`, `BorderRadius.zero`, not `CircleAvatar` / capsule buttons
- Tags and default colors never share ids or FKs; same ARGB is coincidence
- Both tables may be empty; never block “last row” deletes; never prompt rebind
- One tag per task (`task.tag_id`); drop attached tags / `task_tag`
- Override stores `override_argb` (copied int), not a swatch/tag id
- Fallback ARGB is `0xFF457BD9` (霁蓝)
- Hex picker stays `#RGB` / `#RRGGBB`; illegal hex does not write
- Do not change urgency curve shape, gantt geometry, or add cloud/dark-theme shell
- Commit only when the user asks (repo convention); still mark logical commit boundaries per task
- After Task 1–2 the app may not compile; run only the tests named in that task until Task 4+

## File map

| File | Responsibility |
| --- | --- |
| `lib/domain/models/tag.dart` | Tag: id, name, argb, sortOrder |
| `lib/domain/models/default_color.dart` | DefaultColor: id, argb, isCurrent, sortOrder |
| `lib/domain/models/task.dart` | `tagId`, `overrideArgb`; drop swatch ids |
| `lib/domain/gantt/paint_resolve.dart` | `kFallbackArgb`, `resolveTaskArgb` |
| `lib/domain/gantt/tag_filter.dart` | Match on single `tagId` |
| `lib/domain/gantt/urgency_palette.dart` | Paint from ARGB → HSL |
| `lib/domain/gantt/factory_swatches.dart` | Keep 8-color seed **only** for v1→v2; export `kFallbackArgb` |
| `lib/data/sqlite/app_database.dart` | schemaVersion 3, onCreate schema 3 |
| `lib/data/sqlite/swatch_migration.dart` | Keep v1→v2; add `migrateV2toV3` |
| `lib/platform/task_repository.dart` | Tag + default-color APIs; drop swatch rebind |
| `lib/data/sqlite/sqlite_task_repository.dart` | Implement new APIs |
| `lib/domain/backup/backup_document.dart` | Backup v3 |
| `lib/data/backup/backup_service.dart` | Export/import v3 (+ v1/v2 upgrade) |
| `lib/app.dart` | Theme from current default color |
| `lib/ui/common/rect_swatch.dart` | 60×30 sharp chip |
| `lib/ui/settings/settings_page.dart` | 标签 + 默认色 lists |
| `lib/ui/task/task_form_page.dart` | One tag + override ARGB chips |
| `lib/ui/day/day_gantt_page.dart` | Resolve ARGB; one-tag create |
| `lib/ui/week/week_gantt_page.dart` | Same |
| `lib/ui/month/month_page.dart` | Same |
| `lib/ui/shell/app_shell.dart` | Filter chips use `tag.argb` |
| Delete | `lib/domain/models/color_swatch.dart`, `lib/ui/common/swatch_picker.dart`, `lib/ui/settings/swatch_inline_host.dart` after UI cutover |

---

### Task 1: Domain models, resolve, filter

**Files:**
- Modify: `lib/domain/models/tag.dart`
- Create: `lib/domain/models/default_color.dart`
- Modify: `lib/domain/models/task.dart`
- Create: `lib/domain/gantt/paint_resolve.dart`
- Modify: `lib/domain/gantt/tag_filter.dart`
- Modify: `lib/domain/gantt/factory_swatches.dart` (add `kFallbackArgb`)
- Test: `test/domain/swatch_resolve_test.dart` → rewrite as `test/domain/paint_resolve_test.dart`
- Test: `test/domain/tag_filter_test.dart`

**Interfaces:**
- Consumes: none
- Produces:
  - `const int kFallbackArgb = 0xFF457BD9;`
  - `class Tag { id, name, argb, sortOrder }`
  - `class DefaultColor { id, argb, isCurrent, sortOrder }`
  - `class Task { … tagId, overrideArgb; no autoSwatchId/primaryTagId/overrideSwatchId }`
  - `int resolveTaskArgb(Task task, Map<String, Tag> tags, {int? currentDefaultArgb})`
  - `bool taskMatchesTagFilter({required String? tagId, required Set<String> filterTagIds})`

- [ ] **Step 1: Write failing tests**

Replace `test/domain/tag_filter_test.dart`:

```dart
import 'package:ganttday/domain/gantt/tag_filter.dart';
import 'package:test/test.dart';

void main() {
  test('empty filter matches everything', () {
    expect(
      taskMatchesTagFilter(tagId: null, filterTagIds: const {}),
      isTrue,
    );
    expect(
      taskMatchesTagFilter(tagId: 'a', filterTagIds: const {}),
      isTrue,
    );
  });

  test('matches the single tag', () {
    expect(
      taskMatchesTagFilter(tagId: 'work', filterTagIds: {'work'}),
      isTrue,
    );
  });

  test('rejects a different tag', () {
    expect(
      taskMatchesTagFilter(tagId: 'work', filterTagIds: {'sport'}),
      isFalse,
    );
  });

  test('untagged task is hidden when a filter is on', () {
    expect(
      taskMatchesTagFilter(tagId: null, filterTagIds: {'work'}),
      isFalse,
    );
  });
}
```

Create `test/domain/paint_resolve_test.dart`:

```dart
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/gantt/paint_resolve.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:test/test.dart';

Task _task({String? tagId, int? overrideArgb}) => Task(
      id: '1',
      title: 'x',
      plannedStart: 0,
      plannedEnd: 1,
      tagId: tagId,
      overrideArgb: overrideArgb,
      createdAt: 0,
    );

void main() {
  const tags = {
    'tg': Tag(id: 'tg', name: '学习', argb: 0xFF7EB6F0, sortOrder: 0),
  };

  test('override wins over tag and default', () {
    expect(
      resolveTaskArgb(
        _task(tagId: 'tg', overrideArgb: 0xFF60A5FA),
        tags,
        currentDefaultArgb: 0xFFFFDAC1,
      ),
      0xFF60A5FA,
    );
  });

  test('tag argb used when no override', () {
    expect(
      resolveTaskArgb(_task(tagId: 'tg'), tags, currentDefaultArgb: 0xFFFFDAC1),
      0xFF7EB6F0,
    );
  });

  test('missing tag falls through to current default', () {
    expect(
      resolveTaskArgb(_task(tagId: 'gone'), tags, currentDefaultArgb: 0xFFFFDAC1),
      0xFFFFDAC1,
    );
  });

  test('no tag uses current default then fallback', () {
    expect(
      resolveTaskArgb(_task(), const {}, currentDefaultArgb: 0xFFFFDAC1),
      0xFFFFDAC1,
    );
    expect(resolveTaskArgb(_task(), const {}), kFallbackArgb);
  });

  test('fallback constant is 霁蓝', () {
    expect(kFallbackArgb, 0xFF457BD9);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `dart test test/domain/tag_filter_test.dart test/domain/paint_resolve_test.dart`

Expected: FAIL (wrong signatures / missing `paint_resolve.dart` / Task fields).

- [ ] **Step 3: Implement models and helpers**

`lib/domain/models/tag.dart`:

```dart
class Tag {
  const Tag({
    required this.id,
    required this.name,
    required this.argb,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final int argb;
  final int sortOrder;
}
```

`lib/domain/models/default_color.dart`:

```dart
class DefaultColor {
  const DefaultColor({
    required this.id,
    required this.argb,
    required this.sortOrder,
    this.isCurrent = false,
  });

  final String id;
  final int argb;
  final int sortOrder;
  final bool isCurrent;
}
```

Rewrite `Task`: drop `primaryTagId`, `autoSwatchId`, `overrideSwatchId`. Add `tagId`, `overrideArgb`. `copyWith` flags: `clearTag`, `clearOverrideArgb`.

`lib/domain/gantt/paint_resolve.dart`:

```dart
import '../models/tag.dart';
import '../models/task.dart';
import 'factory_swatches.dart';

int resolveTaskArgb(
  Task task,
  Map<String, Tag> tags, {
  int? currentDefaultArgb,
}) {
  final override = task.overrideArgb;
  if (override != null) return override;
  final tagId = task.tagId;
  if (tagId != null) {
    final tag = tags[tagId];
    if (tag != null) return tag.argb;
  }
  return currentDefaultArgb ?? kFallbackArgb;
}
```

Add to `factory_swatches.dart`:

```dart
const int kFallbackArgb = 0xFF457BD9;
```

`tag_filter.dart`:

```dart
bool taskMatchesTagFilter({
  required String? tagId,
  required Set<String> filterTagIds,
}) {
  if (filterTagIds.isEmpty) return true;
  return tagId != null && filterTagIds.contains(tagId);
}
```

Delete `test/domain/swatch_resolve_test.dart` (replaced). Leave `lib/domain/gantt/swatch_resolve.dart` until Task 10 if other files still import it; or delete it in this task and fix only domain tests first.

- [ ] **Step 4: Run domain tests**

Run: `dart test test/domain/tag_filter_test.dart test/domain/paint_resolve_test.dart`

Expected: PASS

- [ ] **Step 5: Logical commit** — `feat: tag and default color domain models`

---

### Task 2: UrgencyPalette paints from ARGB

**Files:**
- Modify: `lib/domain/gantt/urgency_palette.dart`
- Test: `test/domain/urgency_palette_test.dart`

**Interfaces:**
- Consumes: `ArgbColor.toHsl`
- Produces: `UrgencyPalette.paint({required int argb, …})` — no `ColorSwatch`

- [ ] **Step 1: Rewrite tests to pass `argb:` instead of `base:`**

Use peach `0xFFFFDAC1` and azure `0xFF457BD9`. Derive expected HSL via `ArgbColor.toHsl` in the test (same as production).

- [ ] **Step 2: Run to see FAIL** (`argb` named param missing)

Run: `dart test test/domain/urgency_palette_test.dart`

- [ ] **Step 3: Implement**

```dart
static TaskPaint paint({
  required int argb,
  required WallMinutes plannedStart,
  required WallMinutes plannedEnd,
  required WallMinutes now,
  required bool isDone,
  WallMinutes? actualStart,
  WallMinutes? actualEnd,
  required int urgencyWindowDays,
}) {
  final hsl = ArgbColor.toHsl(argb);
  final baseHue = hsl.hue.round() % 360;
  final swatchPaint = BarPaint(
    hue: baseHue,
    saturation: hsl.saturation,
    lightness: hsl.lightness,
    hatchOverdue: false,
    isPlannedGray: false,
  );
  // existing gray/overdue/complete branching unchanged
}
```

- [ ] **Step 4: Run** `dart test test/domain/urgency_palette_test.dart` — PASS

- [ ] **Step 5: Logical commit** — `feat: paint urgency bars from ARGB`

---

### Task 3: Schema 3 + migrate v2→v3

**Files:**
- Modify: `lib/data/sqlite/app_database.dart`
- Modify: `lib/data/sqlite/swatch_migration.dart`
- Test: `test/data/schema_v2_migration_test.dart` (keep v1→v2)
- Create: `test/data/schema_v3_migration_test.dart`

**Interfaces:**
- Consumes: schema 2 tables `color_swatch`, `tag.swatch_id`, `task.primary_tag_id/auto_swatch_id/override_swatch_id`, `task_tag`
- Produces: `schemaVersion = 3`; `migrateV2toV3`; onCreate seeds **one** `default_color` row (霁蓝, `is_current=1`) and **empty** `tag`

- [ ] **Step 1: Write `schema_v3_migration_test.dart`**

Cover:

1. `AppDatabase.open` on empty db: no `color_swatch` / `task_tag`; `tag` has `argb` not `swatch_id`; `task` has `tag_id` + `override_argb`, no `auto_swatch_id`; `default_color` has one current row `argb == 0xFF457BD9`.
2. In-memory v2 fixture: two tags sharing `azure`; one task with `primary_tag_id` + extra `task_tag`; one task with `override_swatch_id`; then `migrateV2toV3`.
   - Both tags keep ids, each has copied azure ARGB
   - `task.tag_id` = old primary; attached row gone
   - override becomes that swatch’s ARGB int
   - `default_color` has one current row from old `is_default=1`
   - `color_swatch` / `task_tag` dropped

Also keep existing v1→v2 test; `onUpgrade` must still run v1→v2 then v2→v3 when opening v1 files.

- [ ] **Step 2: Run** `dart test test/data/schema_v3_migration_test.dart` — FAIL

- [ ] **Step 3: Implement schema 3**

`applySchema` creates:

```sql
CREATE TABLE tag (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  argb INTEGER NOT NULL,
  sort_order INTEGER NOT NULL
);
CREATE TABLE default_color (
  id TEXT PRIMARY KEY,
  argb INTEGER NOT NULL,
  is_current INTEGER NOT NULL,
  sort_order INTEGER NOT NULL
);
CREATE TABLE task (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  planned_start INTEGER NOT NULL,
  planned_end INTEGER NOT NULL,
  actual_start INTEGER,
  actual_end INTEGER,
  is_done INTEGER NOT NULL DEFAULT 0,
  tag_id TEXT,
  override_argb INTEGER,
  notes TEXT,
  created_at INTEGER NOT NULL
);
```

`onCreate`: `applySchema` then insert default_color `{id: uuid, argb: kFallbackArgb, is_current: 1, sort_order: 0}`. Do **not** call `seedFactorySwatches`.

`onUpgrade`:

```dart
if (oldVersion < 2) await migrateV1toV2(db);
if (oldVersion < 3) await migrateV2toV3(db);
```

`migrateV2toV3` (transaction):

1. Create `default_color`. Copy ARGB from `color_swatch WHERE is_default=1` (else `kFallbackArgb`), `is_current=1`.
2. `ALTER TABLE tag ADD COLUMN argb INTEGER` / `sort_order`; fill argb from join on `swatch_id`; rebuild `tag` without `swatch_id`.
3. Rebuild `task`: `tag_id = primary_tag_id` if that tag exists else null; `override_argb` from override swatch argb; drop auto/override/primary swatch columns.
4. `DROP TABLE task_tag`; `DROP TABLE color_swatch`.

Keep `migrateV1toV2` + `seedFactorySwatches` for the v1 path only.

- [ ] **Step 4: Run** `dart test test/data/schema_v2_migration_test.dart test/data/schema_v3_migration_test.dart` — PASS

- [ ] **Step 5: Logical commit** — `feat: sqlite schema 3 independent tag and default_color`

---

### Task 4: TaskRepository + sqlite

**Files:**
- Modify: `lib/platform/task_repository.dart`
- Modify: `lib/data/sqlite/sqlite_task_repository.dart`
- Test: `test/data/sqlite_task_repository_test.dart`

**Interfaces:**
- Consumes: schema 3, domain models from Task 1
- Produces (replace swatch APIs):

```dart
Future<List<Tag>> listTags();
Future<void> upsertTag(Tag tag); // unique name: throw on conflict
Future<void> deleteTag(String id); // SET task.tag_id NULL; allow deleting last

Future<List<DefaultColor>> listDefaultColors();
Stream<List<DefaultColor>> watchDefaultColors();
Future<DefaultColor?> currentDefaultColor();
Future<void> upsertDefaultColor(DefaultColor color);
/// Inserts with isCurrent=true; clears other is_current.
Future<void> deleteDefaultColor(String id);
/// If deleted was current and rows remain, first remaining (sort_order) becomes current.

Future<void> upsert(Task task); // tag_id + override_argb
```

Remove: `setTaskTags`, `tagIdsForTask`, `listSwatches`, `watchSwatches`, `defaultSwatch`, `upsertSwatch`, `setDefaultSwatch`, `deleteSwatch`. Remove `SwatchOperationException` or rename to `TagOperationException` for duplicate names.

- [ ] **Step 1: Failing repository tests** (in-memory `AppDatabase.open` / `applySchema` + seed one default color)

Tests:

- `upsertTag` then `listTags` returns name+argb; second same name throws
- `deleteTag` nulls `task.tag_id`; deleting the last tag succeeds; `listTags` empty
- `upsertDefaultColor` new row becomes current; previous current cleared
- `deleteDefaultColor` of current with another row left: survivor `isCurrent == true`
- `deleteDefaultColor` last row: `currentDefaultColor()` is null
- `upsert` task with `tagId` + `overrideArgb` round-trips; no `autoSwatchId`

Rewrite existing overnight-task fixtures: drop `autoSwatchId`.

- [ ] **Step 2: Run** `dart test test/data/sqlite_task_repository_test.dart` — FAIL

- [ ] **Step 3: Implement sqlite mapping**

`deleteTag`:

```dart
await txn.update('task', {'tag_id': null}, where: 'tag_id = ?', whereArgs: [id]);
await txn.delete('tag', where: 'id = ?', whereArgs: [id]);
```

`deleteDefaultColor`: delete row; if no `is_current=1` and table non-empty, `UPDATE default_color SET is_current=1 WHERE id = (SELECT id FROM default_color ORDER BY sort_order LIMIT 1)`.

`upsertDefaultColor`: if `color.isCurrent` or inserting new (spec: 新建成为当前), set all `is_current=0` then write this row with `is_current=1`. **Recolor** of a non-current row must pass `isCurrent: false` so it does not steal current. Settings “新建” always sends `isCurrent: true`. Settings “点色块改色” sends existing `isCurrent` unchanged.

- [ ] **Step 4: Run repository tests** — PASS

- [ ] **Step 5: Logical commit** — `feat: repository APIs for independent tags and default colors`

---

### Task 5: Backup v3

**Files:**
- Modify: `lib/domain/backup/backup_document.dart`
- Modify: `lib/data/backup/backup_service.dart`
- Test: `test/data/backup_service_test.dart`

**Interfaces:**
- Produces: `version: 3` JSON with `tags[{id,name,argb,sort_order}]`, `default_colors[{id,argb,is_current,sort_order}]`, tasks `{tag_id, override_argb}` (no swatch fields)
- Import v2: copy tag colors from `color_swatches` by `swatch_id`; default from `is_default`; drop extra `task_tag`; override id → argb
- Import v1: existing hue→swatch path then same as v2→v3

- [ ] **Step 1: Tests**

- Export of a tag+default+overridden task writes version 3 keys
- Import v3 round-trip
- Import v2 fixture (shared swatch two tags) yields two tags with copied ARGB and independent later edits (assert two rows, same argb, different ids)

- [ ] **Step 2: FAIL then implement parse/write**

- [ ] **Step 3: Run** `dart test test/data/backup_service_test.dart` — PASS

- [ ] **Step 4: Logical commit** — `feat: backup format v3`

---

### Task 6: Theme seed from current default color

**Files:**
- Modify: `lib/app.dart`
- Test: `test/domain/theme_seed_test.dart`

**Interfaces:**
- Consumes: `DefaultColor`, `kFallbackArgb`
- Produces: `Color themeSeedFromDefaultColors(Iterable<DefaultColor> colors)` — current row else fallback; `GanttDayApp` listens `watchDefaultColors()`

- [ ] **Step 1: Tests**

```dart
test('theme seed uses isCurrent argb', () {
  expect(
    themeSeedFromDefaultColors([
      const DefaultColor(id: 'a', argb: 0xFF112233, sortOrder: 0),
      const DefaultColor(id: 'b', argb: 0xFFAABBCC, sortOrder: 1, isCurrent: true),
    ]).toARGB32(),
    0xFFAABBCC,
  );
});

test('empty default colors use fallback', () {
  expect(themeSeedFromDefaultColors(const []).toARGB32(), kFallbackArgb);
});
```

- [ ] **Step 2–4: FAIL, implement, PASS**

- [ ] **Step 5: Logical commit** — `feat: theme seed from current default color`

---

### Task 7: RectSwatch + settings page

**Files:**
- Create: `lib/ui/common/rect_swatch.dart`
- Modify: `lib/ui/settings/settings_page.dart`
- Delete usage of: `lib/ui/settings/swatch_inline_host.dart`
- Test: `test/ui/rect_swatch_test.dart`
- Rewrite: `test/ui/settings_swatch_inline_picker_test.dart` → `test/ui/settings_tag_default_color_test.dart`

**Interfaces:**
- Consumes: `showArgbColorPicker`, repository tag/default APIs
- Produces: `RectSwatch` 60×30 radius 0; settings sections `标签` then `默认色` (no `色卡`)

- [ ] **Step 1: Widget tests**

`rect_swatch_test.dart`: pump `RectSwatch(argb: 0xFF457BD9)`; `tester.getSize` is `Size(60, 30)`; decoration `borderRadius` is `BorderRadius.zero`; not a `CircleAvatar`.

Settings tests (pump `SettingsPage` with a fake `TaskRepository` or extract list widgets if the page is too heavy):

- Finds `标签` and `默认色`, does not find a section titled `色卡`
- Tag row: rect then name; tap name shows a `TextField`
- Can have zero tags (no delete disabled state)
- Default color row has no name text

If `SettingsPage` is hard to pump, extract `TagSettingsList` / `DefaultColorSettingsList` as public widgets and test those.

- [ ] **Step 2: FAIL then implement `RectSwatch`**

```dart
class RectSwatch extends StatelessWidget {
  const RectSwatch({
    super.key,
    required this.argb,
    this.selected = false,
    this.onTap,
  });

  static const double width = 60;
  static const double height = 30;

  final int argb;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Color(argb),
        borderRadius: BorderRadius.zero,
        border: Border.all(
          color: selected ? const Color(0xFF111111) : const Color(0xFF3B82C4),
          width: 1,
        ),
      ),
    );
    if (onTap == null) return box;
    return GestureDetector(onTap: onTap, child: box);
  }
}
```

Settings tag row: `RectSwatch` → tap opens `showArgbColorPicker` → `upsertTag` with new argb. Name: tap → `TextField` on submit; empty/duplicate show existing `_message`. Delete: `deleteTag` immediately, no rebind dialog.

Default color row: `RectSwatch(selected: color.isCurrent)` → tap picker → `upsertDefaultColor` **keeping** `isCurrent`. `+ 新建` picker then insert `isCurrent: true`. Delete: `deleteDefaultColor`. Empty list allowed.

Section order: 可视时段, 紧迫窗口, 标签, 默认色, 备份.

- [ ] **Step 3: Run** `flutter test test/ui/rect_swatch_test.dart test/ui/settings_tag_default_color_test.dart` — PASS

- [ ] **Step 4: Logical commit** — `feat: 60x30 settings lists for tags and default colors`

---

### Task 8: Task form — one tag + override ARGB

**Files:**
- Modify: `lib/ui/task/task_form_page.dart`
- Modify: `lib/ui/day/day_gantt_page.dart` (drag-create `tagId` from single filter)
- Test: add `test/ui/task_form_tag_override_test.dart` (pump form with fake services if possible; otherwise extract `TagPickList` / `OverrideArgbRow`)

**Interfaces:**
- Consumes: `listTags`, `listDefaultColors`, `RectSwatch`
- Produces: form fields `tagId` (null = 无) and optional `overrideArgb`

- [ ] **Step 1: Tests**

- Shows `标签` not `主标签` / `附加标签`
- Selecting a tag row sets one id; `无` clears it
- Override switch on shows 60×30 chips built from **union of tag argbs and default-color argbs** (unique by argb is OK but not required)
- Saving writes `Task.tagId` / `Task.overrideArgb` and does **not** call `setTaskTags`

Drag-create in day page: `tagId: filterTagIds.length == 1 ? filterTagIds.single : null`; no `defaultSwatch()`; no `autoSwatchId`. Snackbar for multi-filter create: keep similar copy if the new task’s `tagId` is not in the filter set.

- [ ] **Step 2–4: FAIL, implement, PASS**

Override chips: `onTap` sets `_overrideArgb = chipArgb`. Both lists empty: tap switch on → `showArgbColorPicker`. Switch off → `_overrideArgb = null`.

- [ ] **Step 5: Logical commit** — `feat: task form single tag and override ARGB`

---

### Task 9: Day / week / month / shell paint and filter

**Files:**
- Modify: `lib/ui/day/day_gantt_page.dart` (`buildTableRows` / `buildPlacedBars`)
- Modify: `lib/ui/week/week_gantt_page.dart`
- Modify: `lib/ui/month/month_page.dart`
- Modify: `lib/ui/shell/app_shell.dart`
- Test: `test/domain/tag_filter_test.dart` already covers match; update any UI tests that pass `primaryTagId` / `attachedTagIds` / `swatchesById`

**Interfaces:**
- Consumes: `resolveTaskArgb`, `taskMatchesTagFilter(tagId:)`, `watchDefaultColors`, `listTags`
- Produces: bars painted from resolved ARGB; filter menu uses `tag.argb` on `RectSwatch` or a 60×30 leading chip (not `CircleAvatar`)

- [ ] **Step 1: Change `buildTableRows` signature**

```dart
final argb = resolveTaskArgb(
  task,
  tags,
  currentDefaultArgb: currentDefault?.argb,
);
final paint = UrgencyPalette.paint(argb: argb, …);
```

Remove `swatchesById` / `ColorSwatch` from these pages. Load `listTags` + `watchDefaultColors` (or list once + change bus). Filter:

```dart
taskMatchesTagFilter(tagId: t.tagId, filterTagIds: widget.filterTagIds)
```

Shell filter: `CircleAvatar(backgroundColor: Color(tag.argb))` → `RectSwatch(argb: tag.argb)` (may scale down in the menu if 60×30 is huge; **spec says 设置页 / 任务表单 / 覆盖选色 / 默认色**. AppBar menu may keep a smaller rect but **still zero radius** — use `RectSwatch` as-is unless it overflows; then a `SizedBox` is a spec violation, so keep 60×30).

- [ ] **Step 2: `flutter test` the affected UI tests + `test/widget_test.dart`**

Fix compile errors in `test/ui/day_gesture_math_test.dart` (drop `autoSwatchId`).

- [ ] **Step 3: Logical commit** — `feat: gantt views resolve independent tag and default colors`

---

### Task 10: Delete dead swatch code + README

**Files:**
- Delete: `lib/domain/models/color_swatch.dart` if unused
- Delete: `lib/ui/common/swatch_picker.dart`
- Delete: `lib/ui/settings/swatch_inline_host.dart`
- Delete: `lib/domain/gantt/swatch_resolve.dart` if superseded by `paint_resolve.dart`
- Keep: `factory_swatches.dart` 8-color list **only** as v1→v2 seed
- Modify: `README.md` (标签 / 色卡 / 备份 version 3)
- Modify: `tools/seed_from_ex.dart` — insert `tag_id` / no swatch columns
- Grep: `ColorSwatch`, `autoSwatchId`, `primaryTagId`, `overrideSwatchId`, `listSwatches`, `task_tag`, `色卡`

- [ ] **Step 1: `rg` the workspace for leftover symbols; fix until `flutter test` is green**

- [ ] **Step 2: README**

- 任务可挂 **一个** 标签（决定颜色，除非覆盖）
- 设置里 **标签** 与 **默认色** 分开管理，色块 60×30 直角
- 备份 version **3**
- 去掉「色卡 id 绑定」说法

- [ ] **Step 3: Run** `flutter test` — all PASS

- [ ] **Step 4: Logical commit** — `chore: remove shared color_swatch and document v3`

---

## Spec coverage (self-review)

| Spec section | Task |
| --- | --- |
| 3.1 标签 60×30 竖排、改色/改名/可删光 | 7 |
| 3.2 默认色独立、点色块只改色、新建为当前、删当前静默顶上、可删光 | 4, 7 |
| 4.1 一个标签 | 8, 9 |
| 4.2 覆盖 ARGB 拷贝、空列表走取色器 | 8 |
| 4.3 解析顺序 + 主题 + 紧迫度 S/L | 1, 2, 6, 9 |
| 5 删除与空表 | 4 |
| 6 数据模型 | 1, 3 |
| 7.1 schema 2→3 / onCreate | 3 |
| 7.2 备份 v3 / 导入 v1 v2 | 5 |
| 8 重名、空名、色块尺寸、筛选只看 tag_id | 4, 7, 9 |
| 9 非目标 | not implemented |

No TBD. `UrgencyPalette.paint` uses `argb` everywhere after Task 2. Repository `upsertDefaultColor` distinguishes 新建（isCurrent true）vs 改色（preserve isCurrent）as specified in Task 4.
