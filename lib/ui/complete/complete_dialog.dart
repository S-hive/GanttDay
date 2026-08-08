import 'package:flutter/material.dart';

import '../../domain/gantt/complete_axis.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';

/// Pure overflow ranges for the complete dialog accent (tested separately).
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
}

/// Dialog for marking a task complete and editing actual start/end.
Future<({WallMinutes start, WallMinutes end})?> showCompleteDialog(
  BuildContext context, {
  required Task task,
}) {
  return showDialog<({WallMinutes start, WallMinutes end})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CompleteDialog(task: task),
  );
}

class _CompleteDialog extends StatefulWidget {
  const _CompleteDialog({required this.task});

  final Task task;

  @override
  State<_CompleteDialog> createState() => _CompleteDialogState();
}

class _CompleteDialogState extends State<_CompleteDialog> {
  late AxisWindow _window;
  late WallMinutes _selStart;
  late WallMinutes _selEnd;
  _Handle? _dragHandle;

  @override
  void initState() {
    super.initState();
    final t = widget.task;
    _selStart = t.actualStart ?? t.plannedStart;
    _selEnd = t.actualEnd ?? t.plannedEnd;
    _window = CompleteAxis.initial(
      plannedStart: t.plannedStart,
      plannedEnd: t.plannedEnd,
    );
  }

  String _fmt(WallMinutes m) {
    final dt = WallClock.dateTime(m);
    return '${dt.month}/${dt.day} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _settle() {
    setState(() {
      _dragHandle = null;
      _window = CompleteAxis.ensureVisible(
        current: _window,
        selStart: _selStart,
        selEnd: _selEnd,
        widthPx: 600,
        pointerDown: false,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final overflows = CompleteDialogLogic.overflows(
      plannedStart: t.plannedStart,
      plannedEnd: t.plannedEnd,
      selStart: _selStart,
      selEnd: _selEnd,
    );

    return AlertDialog(
      title: Text('完成：${t.title}'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '实际时间：${_fmt(_selStart)} → ${_fmt(_selEnd)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '计划参考：${_fmt(t.plannedStart)} → ${_fmt(t.plannedEnd)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.black54,
                  ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final width = constraints.maxWidth;
              final geo = GanttGeometry(
                viewStart: _window.viewStart,
                viewEnd: _window.viewEnd,
                widthPx: width,
              );
              return SizedBox(
                height: 96,
                child: _AxisCanvas(
                  geo: geo,
                  plannedStart: t.plannedStart,
                  plannedEnd: t.plannedEnd,
                  selStart: _selStart,
                  selEnd: _selEnd,
                  leftOverflow: overflows.left,
                  rightOverflow: overflows.right,
                  onDragStart: (handle, x) {
                    setState(() => _dragHandle = handle);
                    _applyDrag(handle, geo, x, width);
                  },
                  onDragUpdate: (x) {
                    if (_dragHandle == null) return;
                    _applyDrag(_dragHandle!, geo, x, width);
                  },
                  onDragEnd: _settle,
                ),
              );
            }),
            if (overflows.left != null || overflows.right != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (overflows.left != null) '← 提前开工',
                  if (overflows.right != null) '超时收尾 →',
                ].join('　'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (start: _selStart, end: _selEnd),
          ),
          child: const Text('确认完成'),
        ),
      ],
    );
  }

  void _applyDrag(_Handle handle, GanttGeometry geo, double x, double width) {
    setState(() {
      final t = geo.snap(geo.timeOf(x));
      if (handle == _Handle.start) {
        final latest = _selEnd - GanttGeometry.minDurationMinutes;
        _selStart = t > latest ? latest : t;
      } else {
        _selEnd = geo.clampDuration(start: _selStart, end: t);
      }
      _window = CompleteAxis.ensureVisible(
        current: _window,
        selStart: _selStart,
        selEnd: _selEnd,
        widthPx: width,
        pointerDown: true,
      );
    });
  }
}

enum _Handle { start, end }

class _AxisCanvas extends StatelessWidget {
  const _AxisCanvas({
    required this.geo,
    required this.plannedStart,
    required this.plannedEnd,
    required this.selStart,
    required this.selEnd,
    required this.leftOverflow,
    required this.rightOverflow,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final GanttGeometry geo;
  final WallMinutes plannedStart;
  final WallMinutes plannedEnd;
  final WallMinutes selStart;
  final WallMinutes selEnd;
  final (int, int)? leftOverflow;
  final (int, int)? rightOverflow;
  final void Function(_Handle handle, double x) onDragStart;
  final void Function(double x) onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) {
          final x = d.localPosition.dx;
          final startX = geo.xOf(selStart);
          final endX = geo.xOf(selEnd);
          final handle = (x - startX).abs() <= (x - endX).abs()
              ? _Handle.start
              : _Handle.end;
          onDragStart(handle, x);
        },
        onHorizontalDragUpdate: (d) => onDragUpdate(d.localPosition.dx),
        onHorizontalDragEnd: (_) => onDragEnd(),
        onHorizontalDragCancel: onDragEnd,
        child: CustomPaint(
          size: Size(constraints.maxWidth, 96),
          painter: _CompleteAxisPainter(
            geo: geo,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            selStart: selStart,
            selEnd: selEnd,
            leftOverflow: leftOverflow,
            rightOverflow: rightOverflow,
          ),
        ),
      );
    });
  }
}

class _CompleteAxisPainter extends CustomPainter {
  _CompleteAxisPainter({
    required this.geo,
    required this.plannedStart,
    required this.plannedEnd,
    required this.selStart,
    required this.selEnd,
    required this.leftOverflow,
    required this.rightOverflow,
  });

  final GanttGeometry geo;
  final WallMinutes plannedStart;
  final WallMinutes plannedEnd;
  final WallMinutes selStart;
  final WallMinutes selEnd;
  final (int, int)? leftOverflow;
  final (int, int)? rightOverflow;

  @override
  void paint(Canvas canvas, Size size) {
    final axisY = size.height / 2;

    // Axis line
    canvas.drawLine(
      Offset(0, axisY),
      Offset(size.width, axisY),
      Paint()
        ..color = Colors.black26
        ..strokeWidth = 1,
    );

    // Planned reference (gray, smaller, locked)
    final planLeft = geo.xOf(plannedStart);
    final planRight = geo.xOf(plannedEnd);
    final planRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(planLeft, axisY - 10, planRight, axisY + 10),
      const Radius.circular(4),
    );
    canvas.drawRRect(planRect, Paint()..color = Colors.black12);
    canvas.drawRRect(
      planRect,
      Paint()
        ..color = Colors.black26
        ..style = PaintingStyle.stroke,
    );

    // Overflow accents (dialog-only)
    final accent = Paint()..color = const Color(0xFFE53935).withValues(alpha: 0.55);
    if (leftOverflow != null) {
      final l = geo.xOf(leftOverflow!.$1);
      final r = geo.xOf(leftOverflow!.$2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(l, axisY - 18, r, axisY + 18),
          const Radius.circular(4),
        ),
        accent,
      );
    }
    if (rightOverflow != null) {
      final l = geo.xOf(rightOverflow!.$1);
      final r = geo.xOf(rightOverflow!.$2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(l, axisY - 18, r, axisY + 18),
          const Radius.circular(4),
        ),
        accent,
      );
    }

    // Selection bar
    final selLeft = geo.xOf(selStart);
    final selRight = geo.xOf(selEnd);
    final selRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(selLeft, axisY - 16, selRight, axisY + 16),
      const Radius.circular(6),
    );
    canvas.drawRRect(selRect, Paint()..color = const Color(0xFF4A6CF7).withValues(alpha: 0.45));
    canvas.drawRRect(
      selRect,
      Paint()
        ..color = const Color(0xFF4A6CF7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Handles
    _drawHandle(canvas, Offset(selLeft, axisY));
    _drawHandle(canvas, Offset(selRight, axisY));
  }

  void _drawHandle(Canvas canvas, Offset c) {
    canvas.drawCircle(c, 8, Paint()..color = Colors.white);
    canvas.drawCircle(
      c,
      8,
      Paint()
        ..color = const Color(0xFF4A6CF7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(covariant _CompleteAxisPainter old) =>
      old.geo != geo ||
      old.selStart != selStart ||
      old.selEnd != selEnd ||
      old.leftOverflow != leftOverflow ||
      old.rightOverflow != rightOverflow;
}
