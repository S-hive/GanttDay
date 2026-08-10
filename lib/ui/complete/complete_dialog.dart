import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/gantt/complete_axis.dart';
import '../../domain/gantt/day_gesture_math.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/gantt/urgency_palette.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../day/bar_time_label.dart';
import '../day/day_gantt_painter.dart';

/// Pure helpers for the complete dialog (tested separately).
class CompleteDialogLogic {
  CompleteDialogLogic._();

  static ({(int, int)? left, (int, int)? right}) overflows({
    required WallMinutes plannedStart,
    required WallMinutes plannedEnd,
    required WallMinutes selStart,
    required WallMinutes selEnd,
  }) {
    (int, int)? left;
    (int, int)? right;
    if (selStart < plannedStart) left = (selStart, plannedStart);
    if (selEnd > plannedEnd) right = (plannedEnd, selEnd);
    return (left: left, right: right);
  }

  /// Horizontal hit on the actual bar, including a small edge pad.
  static bool hitsSelectionBar({
    required double x,
    required double selLeft,
    required double selRight,
    double handlePad = 8,
  }) {
    final left = selLeft < selRight ? selLeft : selRight;
    final right = selLeft < selRight ? selRight : selLeft;
    return x >= left - handlePad && x <= right + handlePad;
  }

  static bool shouldUncompleteOnSecondaryTap({
    required bool isDone,
    required bool hitSelectionBar,
  }) =>
      isDone && hitSelectionBar;

  /// Hour marks for the mini day canvas (same labeling rules as day view).
  static List<HourMark> hourMarksFor({
    required GanttGeometry geo,
    required WallMinutes pageDay0,
  }) {
    final pageDay = WallClock.dateTime(pageDay0);
    final marks = <HourMark>[];
    final startAligned = (geo.viewStart ~/ 60) * 60;
    for (var t = startAligned; t <= geo.viewEnd; t += 60) {
      if (t < geo.viewStart) continue;
      final dt = WallClock.dateTime(t);
      final otherDay = dt.day != pageDay.day ||
          dt.month != pageDay.month ||
          dt.year != pageDay.year;
      final midnightMark = t > pageDay0 && otherDay && dt.hour == 0;
      marks.add(HourMark(
        x: geo.xOf(t),
        label: midnightMark ? '${dt.month}/${dt.day}' : '${dt.hour}:00',
        emphasized: t == geo.viewStart ||
            t == geo.viewEnd ||
            midnightMark ||
            dt.hour % 6 == 0,
        isDayBoundary: midnightMark,
      ));
    }
    return marks;
  }
}

/// Result of [showCompleteDialog]; `null` means cancelled.
sealed class CompleteDialogResult {
  const CompleteDialogResult();
}

class CompleteDialogSaved extends CompleteDialogResult {
  const CompleteDialogSaved({required this.start, required this.end});

  final WallMinutes start;
  final WallMinutes end;
}

class CompleteDialogUncomplete extends CompleteDialogResult {
  const CompleteDialogUncomplete();
}

/// Dialog for marking a task complete and editing actual start/end.
///
/// [referencePaint] colors the fixed planned reference bar (caller's swatch).
Future<CompleteDialogResult?> showCompleteDialog(
  BuildContext context, {
  required Task task,
  required BarPaint referencePaint,
}) {
  return showDialog<CompleteDialogResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CompleteDialog(
      task: task,
      referencePaint: referencePaint,
    ),
  );
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({
    required this.task,
    required this.referencePaint,
  });

  final Task task;
  final BarPaint referencePaint;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  static const double _canvasHeight = 200;

  late AxisWindow _window;
  /// Committed actual span; null until the user finishes a create drag
  /// (unless the task already has actuals).
  WallMinutes? _actualStart;
  WallMinutes? _actualEnd;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    if (t.isDone && t.actualStart != null && t.actualEnd != null) {
      _actualStart = t.actualStart;
      _actualEnd = t.actualEnd;
    }
    _window = CompleteAxis.initial(
      plannedStart: t.plannedStart,
      plannedEnd: t.plannedEnd,
    );
  }

  ({WallMinutes start, WallMinutes end}) get _saveSpan {
    final a = _actualStart;
    final b = _actualEnd;
    if (a != null && b != null) return (start: a, end: b);
    final t = widget.task;
    return (start: t.plannedStart, end: t.plannedEnd);
  }

  void _onActualCommitted(WallMinutes start, WallMinutes end, double width) {
    setState(() {
      _actualStart = start;
      _actualEnd = end;
      _window = CompleteAxis.ensureVisible(
        current: _window,
        selStart: start,
        selEnd: end,
        widthPx: width,
        pointerDown: false,
      );
    });
  }

  void _onCreating(WallMinutes start, WallMinutes end, double width) {
    setState(() {
      _window = CompleteAxis.ensureVisible(
        current: _window,
        selStart: start,
        selEnd: end,
        widthPx: width,
        pointerDown: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final theme = Theme.of(context);
    final pageDay0 = WallClock.dayStart(t.plannedStart);

    return AlertDialog(
      title: Text(t.isDone ? '修改实际时间：${t.title}' : '设置实际时间：${t.title}'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                t.isDone
                    ? '长按拖拽重设实际时间（与日视图建条相同）；右键实际时间条取消完成'
                    : '长按拖拽设置实际时间（与日视图建条相同）；色块条为计划参考，拖拽时不移动',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.black45,
                ),
              ),
            ),
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final geo = GanttGeometry(
                viewStart: _window.viewStart,
                viewEnd: _window.viewEnd,
                widthPx: width,
              );
              final hourMarks = CompleteDialogLogic.hourMarksFor(
                geo: geo,
                pageDay0: pageDay0,
              );
              return SizedBox(
                key: const Key('complete-axis'),
                height: _canvasHeight,
                child: _MiniDayCanvas(
                  geo: geo,
                  hourMarks: hourMarks,
                  title: t.title,
                  plannedStart: t.plannedStart,
                  plannedEnd: t.plannedEnd,
                  referencePaint: widget.referencePaint,
                  actualStart: _actualStart,
                  actualEnd: _actualEnd,
                  canUncomplete: t.isDone,
                  previewColor: theme.colorScheme.primary,
                  onCreating: (s, e) => _onCreating(s, e, width),
                  onActualCommitted: (s, e) =>
                      _onActualCommitted(s, e, width),
                  onUncomplete: () => Navigator.of(context).pop(
                    const CompleteDialogUncomplete(),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        if (t.isDone)
          TextButton(
            onPressed: () => Navigator.of(context).pop(
              const CompleteDialogUncomplete(),
            ),
            child: const Text('取消完成'),
          ),
        FilledButton(
          onPressed: () {
            final span = _saveSpan;
            Navigator.of(context).pop(
              CompleteDialogSaved(start: span.start, end: span.end),
            );
          },
          child: Text(t.isDone ? '保存' : '确认完成'),
        ),
      ],
    );
  }
}

class _MiniDayCanvas extends StatefulWidget {
  const _MiniDayCanvas({
    required this.geo,
    required this.hourMarks,
    required this.title,
    required this.plannedStart,
    required this.plannedEnd,
    required this.referencePaint,
    required this.actualStart,
    required this.actualEnd,
    required this.canUncomplete,
    required this.previewColor,
    required this.onCreating,
    required this.onActualCommitted,
    required this.onUncomplete,
  });

  final GanttGeometry geo;
  final List<HourMark> hourMarks;
  final String title;
  final WallMinutes plannedStart;
  final WallMinutes plannedEnd;
  final BarPaint referencePaint;
  final WallMinutes? actualStart;
  final WallMinutes? actualEnd;
  final bool canUncomplete;
  final Color previewColor;
  final void Function(WallMinutes start, WallMinutes end) onCreating;
  final void Function(WallMinutes start, WallMinutes end) onActualCommitted;
  final VoidCallback onUncomplete;

  @override
  State<_MiniDayCanvas> createState() => _MiniDayCanvasState();
}

class _MiniDayCanvasState extends State<_MiniDayCanvas> {
  static const Duration _longPressCreate = Duration(milliseconds: 350);

  int? _activePointer;
  Offset _downPos = Offset.zero;
  Timer? _longPressTimer;
  bool _creating = false;
  double _anchorX = 0;
  double _currentX = 0;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  void _tryUncompleteAt(Offset local) {
    final a = widget.actualStart;
    final b = widget.actualEnd;
    if (a == null || b == null) return;
    final hit = CompleteDialogLogic.hitsSelectionBar(
      x: local.dx,
      selLeft: widget.geo.xOf(a),
      selRight: widget.geo.xOf(b),
    );
    if (CompleteDialogLogic.shouldUncompleteOnSecondaryTap(
      isDone: widget.canUncomplete,
      hitSelectionBar: hit,
    )) {
      widget.onUncomplete();
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons == kSecondaryMouseButton) {
      _tryUncompleteAt(e.localPosition);
      return;
    }
    if (e.buttons != kPrimaryButton) return;
    _activePointer = e.pointer;
    _downPos = e.localPosition;
    _longPressTimer?.cancel();
    if (e.localPosition.dy <= DayGanttLayout.headerHeight) return;
    _longPressTimer = Timer(_longPressCreate, () {
      if (!mounted || _activePointer != e.pointer) return;
      setState(() {
        _creating = true;
        _anchorX = clampXToView(widget.geo, _downPos.dx);
        _currentX = _anchorX;
      });
      final span = proposeCreate(widget.geo, _anchorX, _currentX);
      widget.onCreating(span.start, span.end);
    });
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_activePointer != e.pointer) return;
    if (!_creating) {
      if ((e.localPosition - _downPos).distance > kTouchSlop) {
        _longPressTimer?.cancel();
      }
      return;
    }
    setState(() {
      _currentX = clampXToView(widget.geo, e.localPosition.dx);
    });
    final span = proposeCreate(widget.geo, _anchorX, _currentX);
    widget.onCreating(span.start, span.end);
  }

  void _onPointerUp(PointerUpEvent e) {
    if (_activePointer != e.pointer) return;
    _activePointer = null;
    _longPressTimer?.cancel();
    if (!_creating) return;
    final span = proposeCreate(widget.geo, _anchorX, _currentX);
    setState(() => _creating = false);
    widget.onActualCommitted(span.start, span.end);
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_activePointer != e.pointer) return;
    _activePointer = null;
    _longPressTimer?.cancel();
    if (_creating) setState(() => _creating = false);
  }

  @override
  Widget build(BuildContext context) {
    final size = Size(widget.geo.widthPx, 200);
    ({WallMinutes start, WallMinutes end})? createPreview;
    if (_creating) {
      createPreview = proposeCreate(widget.geo, _anchorX, _currentX);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: size,
                painter: _MiniDayPainter(
                  geo: widget.geo,
                  hourMarks: widget.hourMarks,
                  title: widget.title,
                  plannedStart: widget.plannedStart,
                  plannedEnd: widget.plannedEnd,
                  referencePaint: widget.referencePaint,
                  actualStart: widget.actualStart,
                  actualEnd: widget.actualEnd,
                  accentColor: widget.previewColor,
                ),
              ),
              if (createPreview != null)
                _CreatePreviewBar(
                  geo: widget.geo,
                  start: createPreview.start,
                  end: createPreview.end,
                  color: widget.previewColor,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatePreviewBar extends StatelessWidget {
  const _CreatePreviewBar({
    required this.geo,
    required this.start,
    required this.end,
    required this.color,
  });

  final GanttGeometry geo;
  final WallMinutes start;
  final WallMinutes end;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final left = geo.xOf(start);
    final right = geo.xOf(end);
    final top = DayGanttLayout.headerHeight + DayGanttLayout.barGap;
    return Positioned(
      left: left,
      top: top,
      width: math.max(right - left, 2),
      height: DayGanttLayout.barHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            border: Border.all(color: color, width: 1.5),
          ),
        ),
      ),
    );
  }
}

class _MiniDayPainter extends CustomPainter {
  _MiniDayPainter({
    required this.geo,
    required this.hourMarks,
    required this.title,
    required this.plannedStart,
    required this.plannedEnd,
    required this.referencePaint,
    required this.actualStart,
    required this.actualEnd,
    required this.accentColor,
  });

  final GanttGeometry geo;
  final List<HourMark> hourMarks;
  final String title;
  final WallMinutes plannedStart;
  final WallMinutes plannedEnd;
  final BarPaint referencePaint;
  final Color accentColor;
  final WallMinutes? actualStart;
  final WallMinutes? actualEnd;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final barTop =
        DayGanttLayout.headerHeight + DayGanttLayout.barGap;

    // Fixed planned reference — caller's swatch color; never moves with create.
    final planLeft = geo.xOf(plannedStart);
    final planRight = geo.xOf(plannedEnd);
    final planRect = Rect.fromLTWH(
      planLeft + 1,
      barTop,
      math.max(planRight - planLeft - 2, 2),
      DayGanttLayout.barHeight,
    );
    final planColor = colorOf(referencePaint);
    canvas.drawRect(
      planRect.shift(const Offset(0, 1.5)),
      Paint()..color = Colors.black.withValues(alpha: 0.08),
    );
    canvas.drawRect(planRect, Paint()..color = planColor);
    canvas.drawRect(
      planRect,
      Paint()
        ..color = borderColorOf(referencePaint).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    _paintCaption(
      canvas,
      planRect,
      title: title,
      start: plannedStart,
      end: plannedEnd,
      fg: textColorOn(referencePaint),
    );

    // Committed actual (below/overlapping — draw after so it sits on top).
    final a = actualStart;
    final b = actualEnd;
    if (a != null && b != null) {
      final selLeft = geo.xOf(a);
      final selRight = geo.xOf(b);
      final selRect = Rect.fromLTWH(
        selLeft + 1,
        barTop,
        math.max(selRight - selLeft - 2, 2),
        DayGanttLayout.barHeight,
      );
      // Actual uses theme primary (default swatch seed) so it matches create preview.
      canvas.drawRect(
        selRect,
        Paint()..color = accentColor.withValues(alpha: 0.88),
      );
      canvas.drawRect(
        selRect,
        Paint()
          ..color = accentColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
      _paintCaption(
        canvas,
        selRect,
        title: title,
        start: a,
        end: b,
        fg: Colors.white,
      );
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.07)
      ..strokeWidth = 1;
    final hourPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    final rowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;

    final bodyHeight =
        math.max(0.0, size.height - DayGanttLayout.headerHeight);
    final paintedRows =
        math.max(1, (bodyHeight / DayGanttLayout.laneHeight).ceil());
    for (var r = 0; r <= paintedRows; r++) {
      final y = DayGanttLayout.headerHeight + r * DayGanttLayout.laneHeight;
      if (y > size.height) break;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), rowPaint);
    }

    for (final mark in hourMarks) {
      canvas.drawLine(
        Offset(mark.x, DayGanttLayout.headerHeight),
        Offset(mark.x, size.height),
        mark.emphasized ? hourPaint : gridPaint,
      );
      if (mark.label.isEmpty) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: mark.label,
          style: TextStyle(
            fontSize: 11,
            color: mark.isDayBoundary
                ? const Color(0xFFC62828)
                : Colors.black.withValues(alpha: 0.55),
            fontWeight: mark.emphasized ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final textOrigin = Offset(mark.x + 4, 8);
      if (mark.isDayBoundary) {
        const padX = 3.0;
        const padY = 1.5;
        final box = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            textOrigin.dx - padX,
            textOrigin.dy - padY,
            tp.width + padX * 2,
            tp.height + padY * 2,
          ),
          const Radius.circular(2),
        );
        canvas.drawRRect(
          box,
          Paint()
            ..color = const Color(0xFFC62828)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
      tp.paint(canvas, textOrigin);
    }

    if (hourMarks.length >= 2) {
      final hourPx = hourMarks[1].x - hourMarks[0].x;
      if (hourPx > 40) {
        final qPaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.04)
          ..strokeWidth = 1;
        for (var i = 0; i < hourMarks.length - 1; i++) {
          final base = hourMarks[i].x;
          for (var q = 1; q < 4; q++) {
            final x = base + hourPx * q / 4;
            canvas.drawLine(
              Offset(x, DayGanttLayout.headerHeight),
              Offset(x, size.height),
              qPaint,
            );
          }
        }
      }
    }
  }

  void _paintCaption(
    Canvas canvas,
    Rect rect, {
    required String title,
    required WallMinutes start,
    required WallMinutes end,
    required Color fg,
  }) {
    final timeText = formatBarTimeLabel(start, end);
    final muted = fg.withValues(alpha: 0.85);
    final line = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: fg,
              height: 1.15,
            ),
          ),
          TextSpan(
            text: '  $timeText',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: muted,
              height: 1.15,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final textX = stickyCaptionLeft(
      barLeft: rect.left,
      barRight: rect.right,
      viewportLeft: rect.left,
      captionWidth: line.width,
    );
    final offset = Offset(
      textX,
      rect.top + (rect.height - line.height) / 2,
    );

    final overflows = captionOverflowsBar(
      textX: textX,
      captionWidth: line.width,
      barLeft: rect.left,
      barRight: rect.right,
    );
    if (!overflows) {
      line.paint(canvas, offset);
      return;
    }

    const outsideFg = Color(0xDE000000);
    final outside = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: outsideFg,
              height: 1.15,
            ),
          ),
          TextSpan(
            text: '  $timeText',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: outsideFg.withValues(alpha: 0.78),
              height: 1.15,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    outside.paint(canvas, offset);
    canvas.save();
    canvas.clipRect(rect);
    line.paint(canvas, offset);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MiniDayPainter old) =>
      old.geo != geo ||
      old.hourMarks != hourMarks ||
      old.title != title ||
      old.plannedStart != plannedStart ||
      old.plannedEnd != plannedEnd ||
      old.referencePaint != referencePaint ||
      old.accentColor != accentColor ||
      old.actualStart != actualStart ||
      old.actualEnd != actualEnd;
}
