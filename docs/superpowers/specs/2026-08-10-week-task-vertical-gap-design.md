# 周视图：同一天任务条纵向间距

- 状态：已确认（聊天设计评审）
- 日期：2026-08-10
- 范围：仅周视图任务条绘制；不改日/月视图；不改 `layoutWeekSlots` 时间几何

## 1. 目标

同一天内相邻（含时间刚好衔接）的任务条之间至少留出 **3px** 纵向空隙，避免视觉上连成一整条。

## 2. 决策摘要

| 项 | 选择 |
| --- | --- |
| 方式 | 每条任务上下各缩 `verticalBarGap/2`（统一内缩） |
| 常量 | `verticalBarGap = 3` |
| 落点 | `_slotPositioned`（绘制/定位时），不碰布局分数 |
| 最短高度 | 保留现有 `height < 18 → 18` |
| 时间语义 | tooltip / 真实起止不变 |

## 3. 几何

对每个 slot：

```
top    = topFrac * dayHeight + verticalBarGap / 2
height = heightFrac * dayHeight - verticalBarGap
if (height < 18) height = 18
```

时间刚好衔接的两条：上条底边与下条顶边相差约 `verticalBarGap`（3px）。横向既有 `left +1.5` / `width -3` 不变。

## 4. 实现落点

- 修改：`lib/ui/week/week_gantt_page.dart` — `_slotPositioned` 应用纵向内缩；抽出纯函数便于单测（输入 `topFrac` / `heightFrac` / `dayHeight`，输出 `top` / `height`）。
- 不改：`lib/ui/week/week_column_layout.dart`、日视图、月视图。

## 5. 验收

- 同一天时间衔接的两条任务，视觉上至少隔开约 3px。
- 非衔接任务同样上下各缩 1.5px（统一规则）。
- 单测：衔接情况下 `next.top - prev.bottom ≈ 3`（在未触发最短高度抬升时）。
- tooltip 与任务真实时间区间不变。
