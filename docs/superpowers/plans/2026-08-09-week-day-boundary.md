# Week Day Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make week-view adjacent day columns visually distinct with a thin red vertical rule.

**Architecture:** Reuse the day-view midnight boundary color (`#C62828`) on `_DayColumn`'s existing left border when `showLeftBorder` is true. No layout or data changes.

**Tech Stack:** Flutter / Dart widget decoration in `week_gantt_page.dart`.

## Global Constraints

- Color `#C62828`, width 1px (spec).
- Only Tuesday–Sunday left edges; Monday unchanged.
- Do not change hour grid, today tint, or now line.

---

### Task 1: Red day-column border

**Files:**
- Modify: `lib/ui/week/week_gantt_page.dart` (`_DayColumn.build` `BorderSide`)
- Spec: `docs/superpowers/specs/2026-08-09-week-day-boundary-design.md`

**Interfaces:**
- Consumes: existing `showLeftBorder` flag
- Produces: red left border when `showLeftBorder` is true

- [x] **Step 1: Change left border color**

In `_DayColumn.build`, replace:

```dart
left: BorderSide(
  color: Colors.black12,
  width: showLeftBorder ? 1 : 0,
),
```

with:

```dart
left: BorderSide(
  color: const Color(0xFFC62828),
  width: showLeftBorder ? 1 : 0,
),
```

- [ ] **Step 2: Visual check**

Hot restart; open week view; confirm red rules between day columns and no other UI regressions.
