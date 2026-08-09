# Week view day-boundary markers

## Problem

Week columns are separated only by a `Colors.black12` 1px left border — the same weight/color as the hour grid — so adjacent-day task bars are hard to tell apart.

## Decision

Use a thin red vertical rule between day columns (option B), matching the day-view midnight date frame color.

## Spec

| Item | Value |
|------|--------|
| Color | `#C62828` |
| Width | 1px |
| Side gaps | 3px blank on left and right of the rule |
| Placement | Between day columns (after Mon…Sat); header / body / now-line share the same separator |
| Monday left edge | No red rule (avoid stacking on the time gutter) |

Out of scope: hour grid, today column tint, header date boxes.

## Implementation note

`lib/ui/week/week_gantt_page.dart` — shared `_dayBoundary()` spacer between `Expanded` day columns.
