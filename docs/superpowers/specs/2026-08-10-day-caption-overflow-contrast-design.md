# 日视图字幕溢出对比度（条内前景色 · 溢出深色）

- 状态：已实现（聊天选定方案 B）
- 日期：2026-08-10
- 范围：日视图甘特条字幕可读性；不改编排/sticky 规则、不裁切文案、不改周/月视图

## 1. 目标

短条（时长窄）时字幕仍完整显示标题 + 时间 meta，且**溢出到浅色网格上的字必须可读**。不把时间信息藏进悬停。

## 2. 问题

日视图故意不裁切字幕（`clipToBar: false`），字色由 `textColorOn(bar.paint)` 按条底色选取（深底白字）。条太短时白字画出条外，落在浅色网格上对比度崩溃。

## 3. 决策摘要

| 项 | 选择 |
| --- | --- |
| 方案 | **B**：条内用 on-bar 前景色，溢出部分用深色 |
| 文案 | 仍完整一行：`标题  开始 – 结束（时长）`（有备注则继续） |
| Sticky | 不变：`stickyCaptionLeft` |
| 不溢出时 | 单层绘制，外观与改前一致 |
| 周/月 | 本轮不做 |

未选：A 条外上下方深色字；C 描边/光晕；D 省略号裁切。

## 4. 行为

### 4.1 溢出判定

`captionOverflowsBar`：字幕布局原点 `textX` 与宽度相对条的左右缘——

- `textX < barLeft`，或
- `textX + captionWidth > barRight`

任一成立即为溢出。

### 4.2 绘制

入口：`DayGanttPainter._paintBarCaption`。

1. 用 `textColorOn` 建 on-bar 层（标题实色、meta α≈0.78）。
2. 算 sticky `textX`；若不溢出 → 只画这一层。
3. 若溢出：
   - **底层**：整行深色（约 `0xDE000000` / black87，meta 同色系降 α），完整画出条外；
   - **顶层**：同一文案的 on-bar 前景色，**`canvas.clipRect(barRect)`** 后绘制。

结果：条矩形内仍是高对比前景色；出条部分露出底层深色，在浅网格上可读。

### 4.3 不变约束

- 不因条宽省略或丢 meta。
- Sticky 与横向滚动行为不变。
- 浅色条（`textColorOn` 已是深字）时双层同色，可接受。

## 5. 代码落点

| 文件 | 职责 |
| --- | --- |
| `lib/ui/day/bar_time_label.dart` | `captionOverflowsBar`；既有 sticky / format 不变 |
| `lib/ui/day/day_gantt_painter.dart` | `_paintBarCaption` 双层绘制 |
| `test/ui/bar_time_label_test.dart` | 溢出判定单测 |

## 6. 验收

- 短条（如约 55m）：整行 `标题  时间（时长）` 可读，条内仍偏白（深色条时）、条外为深色。
- 长条：无多余描边/双色感，与改前一致。
- Sticky 滚动后字幕仍贴视口，溢出规则仍相对**条矩形**判定。
