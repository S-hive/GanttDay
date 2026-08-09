# Day Bar Caption Priority Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a day-view bar cannot fit title + time, show the full task title (overflow allowed) instead of truncated time.

**Architecture:** Extract a pure caption-mode helper next to existing `bar_time_label.dart` helpers; unit-test it; wire `DayGanttPainter._paintBarCaption` to paint full title without bar clip when mode is title-only.

**Tech Stack:** Flutter / Dart, existing `DayGanttPainter` canvas captions.

## Global Constraints

- Day view only; week/month unchanged
- Tight bars: title only, no ellipsis, may paint outside the bar
- Tall bars: keep title + time (+ notes) stack with existing clip behavior
- No new user-facing strings beyond existing title text

---

## File map

| File | Role |
| --- | --- |
| `lib/ui/day/bar_time_label.dart` | Add `BarCaptionMode` + `resolveBarCaptionMode` |
| `test/ui/bar_time_label_test.dart` | Cover mode resolution |
| `lib/ui/day/day_gantt_painter.dart` | Use mode in `!canStack` / paint path |

---

### Task 1: Caption mode helper (TDD)

**Files:**
- Modify: `lib/ui/day/bar_time_label.dart`
- Modify: `test/ui/bar_time_label_test.dart`

- [x] Write failing tests for:
  - `canStack: true` → stack (title + meta, clip unless overflowCaption)
  - `canStack: false` → titleOnlyOverflow (title only, no clip)
  - `overflowCaption: true` → stack with no clip even if canStack false
- [x] Run tests; confirm fail
- [x] Implement `BarCaptionMode` + `resolveBarCaptionMode`
- [x] Run tests; confirm pass

### Task 2: Wire painter

**Files:**
- Modify: `lib/ui/day/day_gantt_painter.dart`

- [x] In `_paintBarCaption`, replace `!canStack` “only time + ellipsis + clip” with title-only overflow paint (full natural title width, no ellipsis, no `clipRect` to bar)
- [x] Keep sticky X + stack path for `canStack` / overnight overflow
- [x] Run `dart test test/ui/bar_time_label_test.dart`

### Task 3: Manual check

- [ ] Short/narrow day bar shows full task name, not `23:15…`
- [ ] Tall bar still shows title + time

**Commit:** only if user asks.
