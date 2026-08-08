import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import 'day_gantt_painter.dart';

// ---------------------------------------------------------------------------
// Pure gesture math (unit-tested; no Flutter dependencies beyond geometry).
// ---------------------------------------------------------------------------

/// Snapped time range for a blank-area drag from [x0] to [x1].
({WallMinutes start, WallMinutes end}) proposeCreate(
    GanttGeometry geo, double x0, double x1) {
  final left = math.min(x0, x1);
  final right = math.max(x0, x1);
  final start = geo.snap(geo.timeOf(left));
  final end = geo.clampDuration(start: start, end: geo.snap(geo.timeOf(right)));
  return (start: start, end: end);
}

/// Whole-bar move by [deltaX] pixels: duration unchanged, start snapped.
Task proposeMove(Task task, GanttGeometry geo, double deltaX) {
  final deltaMinutes =
      (deltaX / geo.widthPx * (geo.viewEnd - geo.viewStart)).round();
  final start = geo.snap(task.plannedStart + deltaMinutes);
  final duration = task.plannedEnd - task.plannedStart;
  return task.copyWith(plannedStart: start, plannedEnd: start + duration);
}

/// Drag the start edge to pixel [x]; never crosses the opposite end
/// (minimum 15 minutes is preserved at the source, spec section 6).
Task proposeResizeStart(Task task, GanttGeometry geo, double x) {
  var start = geo.snap(geo.timeOf(x));
  final latest = task.plannedEnd - GanttGeometry.minDurationMinutes;
  if (start > latest) start = latest;
  return task.copyWith(plannedStart: start);
}

/// Drag the end edge to pixel [x]; clamped to minimum duration.
Task proposeResizeEnd(Task task, GanttGeometry geo, double x) {
  final end =
      geo.clampDuration(start: task.plannedStart, end: geo.snap(geo.timeOf(x)));
  return task.copyWith(plannedEnd: end);
}

// ---------------------------------------------------------------------------
// Gesture layer widget.
// ---------------------------------------------------------------------------

enum _DragMode { none, create, move, resizeStart, resizeEnd }

class DayGanttGestures extends StatefulWidget {
  const DayGanttGestures({
    super.key,
    required this.canvas,
    required this.geo,
    required this.bars,
    required this.tasks,
    required this.onCommitUpdate,
    required this.onCreateRange,
    this.onTapTask,
  });

  final Widget canvas;
  final GanttGeometry geo;
  final List<PlacedBar> bars;
  final List<Task> tasks;

  /// Persist a moved/resized task. Errors are the caller's to surface.
  final Future<void> Function(Task updated) onCommitUpdate;

  /// A blank-area drag finished with this snapped range (open title dialog).
  final void Function(WallMinutes start, WallMinutes end) onCreateRange;

  final void Function(Task task)? onTapTask;

  @override
  State<DayGanttGestures> createState() => _DayGanttGesturesState();
}

class _DayGanttGesturesState extends State<DayGanttGestures> {
  static const double _edgeSlop = 8;

  _DragMode _mode = _DragMode.none;
  Task? _dragTask;
  int _dragLane = 0;
  double _anchorX = 0;
  double _currentX = 0;
  double _grabOffsetX = 0;

  PlacedBar? _barAt(Offset pos) {
    for (final bar in widget.bars) {
      final top = DayGanttLayout.headerHeight +
          bar.lane * DayGanttLayout.laneHeight +
          DayGanttLayout.barGap;
      final rect = Rect.fromLTWH(bar.x - _edgeSlop, top,
          bar.width + 2 * _edgeSlop, DayGanttLayout.laneHeight - 2 * DayGanttLayout.barGap);
      if (rect.contains(pos)) return bar;
    }
    return null;
  }

  Task? _taskOf(PlacedBar bar) {
    for (final t in widget.tasks) {
      if (t.id == bar.taskId) return t;
    }
    return null;
  }

  void _onDragStart(DragStartDetails d) {
    final pos = d.localPosition;
    final bar = _barAt(pos);
    if (bar == null) {
      if (pos.dy > DayGanttLayout.headerHeight) {
        setState(() {
          _mode = _DragMode.create;
          _anchorX = pos.dx;
          _currentX = pos.dx;
        });
      }
      return;
    }
    final task = _taskOf(bar);
    // Completed tasks are frozen in the main view: their planned bar is the
    // reference for the planned/actual comparison (spec section 6).
    if (task == null || task.isDone) return;
    setState(() {
      _dragTask = task;
      _dragLane = bar.lane;
      if ((pos.dx - bar.x).abs() <= _edgeSlop) {
        _mode = _DragMode.resizeStart;
      } else if ((pos.dx - (bar.x + bar.width)).abs() <= _edgeSlop) {
        _mode = _DragMode.resizeEnd;
      } else {
        _mode = _DragMode.move;
        _grabOffsetX = pos.dx;
      }
      _anchorX = pos.dx;
      _currentX = pos.dx;
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_mode == _DragMode.none) return;
    setState(() => _currentX = d.localPosition.dx);
  }

  Future<void> _onDragEnd() async {
    final mode = _mode;
    final task = _dragTask;
    setState(() {
      _mode = _DragMode.none;
      _dragTask = null;
    });
    switch (mode) {
      case _DragMode.none:
        return;
      case _DragMode.create:
        final range = proposeCreate(widget.geo, _anchorX, _currentX);
        widget.onCreateRange(range.start, range.end);
      case _DragMode.move:
        await widget
            .onCommitUpdate(proposeMove(task!, widget.geo, _currentX - _grabOffsetX));
      case _DragMode.resizeStart:
        await widget
            .onCommitUpdate(proposeResizeStart(task!, widget.geo, _currentX));
      case _DragMode.resizeEnd:
        await widget
            .onCommitUpdate(proposeResizeEnd(task!, widget.geo, _currentX));
    }
  }

  Task? _previewTask() {
    final task = _dragTask;
    if (task == null) return null;
    switch (_mode) {
      case _DragMode.move:
        return proposeMove(task, widget.geo, _currentX - _grabOffsetX);
      case _DragMode.resizeStart:
        return proposeResizeStart(task, widget.geo, _currentX);
      case _DragMode.resizeEnd:
        return proposeResizeEnd(task, widget.geo, _currentX);
      case _DragMode.none:
      case _DragMode.create:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final overlays = <Widget>[];
    final theme = Theme.of(context);

    if (_mode == _DragMode.create) {
      final range = proposeCreate(widget.geo, _anchorX, _currentX);
      final left = widget.geo.xOf(range.start);
      final width = widget.geo.xOf(range.end) - left;
      overlays.add(Positioned(
        left: left,
        top: DayGanttLayout.headerHeight,
        width: width,
        height: DayGanttLayout.laneHeight - 2 * DayGanttLayout.barGap,
        child: _previewBox(theme, range.start, range.end),
      ));
    }

    final preview = _previewTask();
    if (preview != null) {
      final left = widget.geo.xOf(preview.plannedStart);
      final width = widget.geo.xOf(preview.plannedEnd) - left;
      overlays.add(Positioned(
        left: left,
        top: DayGanttLayout.headerHeight +
            _dragLane * DayGanttLayout.laneHeight +
            DayGanttLayout.barGap,
        width: width,
        height: DayGanttLayout.laneHeight - 2 * DayGanttLayout.barGap,
        child: _previewBox(theme, preview.plannedStart, preview.plannedEnd),
      ));
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final bar = _barAt(d.localPosition);
        if (bar != null) {
          final task = _taskOf(bar);
          if (task != null) widget.onTapTask?.call(task);
        }
      },
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: (_) => _onDragEnd(),
      onHorizontalDragCancel: () => setState(() {
        _mode = _DragMode.none;
        _dragTask = null;
      }),
      child: Stack(children: [widget.canvas, ...overlays]),
    );
  }

  Widget _previewBox(ThemeData theme, WallMinutes start, WallMinutes end) {
    String hhmm(WallMinutes m) {
      final dt = WallClock.dateTime(m);
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.25),
        border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Text(
        '${hhmm(start)} - ${hhmm(end)}',
        style: TextStyle(fontSize: 11, color: theme.colorScheme.primary),
        overflow: TextOverflow.clip,
        maxLines: 1,
      ),
    );
  }
}
