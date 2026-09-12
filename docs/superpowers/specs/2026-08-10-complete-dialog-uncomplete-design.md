# 完成弹窗：右键蓝条取消完成

- 状态：已确认（聊天：立刻取消、无二次确认）
- 日期：2026-08-10
- 范围：`showCompleteDialog` 结果与日视图接线；沿用既有 `TaskRepository.uncomplete`

## 行为

- 任务已完成时，在弹窗时间轴上右键点中蓝色实际时间条（含两端把手命中区）→ 立即关闭弹窗并 `uncomplete`（清实际起止、`isDone=false`）。
- 同场景也可点弹窗按钮「取消完成」。
- 右键用 `Listener.onPointerDown`（勿与 `onSecondaryTapUp` 叠用，避免二次 `pop`）。
- 未完成任务：右键蓝条无效。
- 左键拖拽、取消/保存按钮不变。

## 结果类型

`CompleteDialogResult`：`save(start,end)` | `uncomplete`；取消仍为 `null`。
