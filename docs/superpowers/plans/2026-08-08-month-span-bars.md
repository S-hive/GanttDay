# Month Span Bars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace month list/`+N` titles with week-row spanning colored bars (title only, ≤10/day, intra-day time insets).

**Architecture:** Pure layout in `month_span_layout.dart` (select visible tasks, week clip → fractions, lanes); `MonthPage` renders week rows with `Stack`/`Positioned` bars.

**Tech Stack:** Flutter/Dart, existing `LaneLayout`, `UrgencyPalette`, `WallClock`.

## Global Constraints

- Max 10 visible bars per calendar day; overflow `+N`
- Bar height ~14–16px; title only
- Cell = 00:00–24:00; start/end days use minute fractions
- Tap day/`+N`/bar → `onOpenDay`
- No drag, no lunar dates

---

### Task 1: `month_span_layout` (TDD)

**Files:**
- Create: `lib/ui/month/month_span_layout.dart`
- Create: `test/ui/month_span_layout_test.dart`

**Produces:**
- `selectVisibleMonthTasks(...)` → visible tasks + `overflowByDay`
- `buildMonthWeekLayouts(...)` → per-week bars with `startFrac`/`endFrac` in `[0,7]`, `lane`, `openDay`

- [x] Failing tests: single-day inset, multi-day continuous frac, cross-week split, max 10 + overflow
- [x] Implement layout helpers
- [x] Tests pass

### Task 2: Rewrite `MonthPage`

**Files:**
- Modify: `lib/ui/month/month_page.dart`

- [x] Load tags + settings (hue/urgency)
- [x] Render week rows + positioned bars; remove list titles
- [x] Wire taps

### Task 3: Verify

- [x] `dart test test/ui/month_span_layout_test.dart`
- [ ] Manual: multi-day bar, single-day inset, `+N` at 11th task

**Commit:** only if user asks.
