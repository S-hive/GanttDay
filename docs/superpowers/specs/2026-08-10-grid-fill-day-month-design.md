# 日/月视图格子线铺满

- 状态：已实现（须保留；曾因未入库被其它改动冲掉）
- 日期：2026-08-10

## 要求

日视图与月视图的格子线须铺满可用视口，不能只画到任务内容高度。

## 日视图

- `lib/ui/day/day_gantt_page.dart`：`paintHeight = max(contentHeight, constraints.maxHeight)`；`CustomPaint` / 滚动容器高度用 `paintHeight`，**不要**再用单独的 `contentHeight` 作为画布高度。
- `lib/ui/day/day_gantt_painter.dart`：横线按 `size.height` 算出足够的 `paintedRows`，不要只画到 `rowCount`。

## 月视图

- `lib/ui/month/month_page.dart`：周行在内容能放下时均分视口高度（`Column` + `Expanded`）；某周内容过高时再 `ListView` 按内容高度滚动。
- `_WeekRow` 接受 `rowHeight`；日格 `Positioned.fill` + `CrossAxisAlignment.stretch`；格线 `CustomPaint` 高度用约束高度。

## 回归注意

改日/月布局或色卡/筛选相关文件时，勿把上述高度逻辑回退成「仅按任务行数算高度」。
