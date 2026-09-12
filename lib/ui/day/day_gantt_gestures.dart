import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/gantt/day_gesture_math.dart';
import '../../domain/gantt/day_span_clamp.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import 'bar_time_label.dart';
import 'day_gantt_painter.dart';

export '../../domain/gantt/day_gesture_math.dart';

// ---------------------------------------------------------------------------
// Gesture layer widget.
// ---------------------------------------------------------------------------

enum _DragMode { none, create, move, resizeStart, resizeEnd }

/// Timeline interactions that do **not** steal blank-area pans from the parent
/// [ScrollView]:
/// - drag on a bar → move / resize
/// - long-press then drag on blank → create
/// - short drag on blank → parent scroll (pan the day)
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
    this.onSecondaryTapBar,
    this.onSecondaryTapEmpty,
    this.onDragTime,
    this.allowBarDrag = true,
  });

  final Widget canvas;
  final GanttGeometry geo;
  final List<PlacedBar> bars;
  final List<Task> tasks;

  final Future<void> Function(Task updated) onCommitUpdate;

  /// [localBarRect] is the create preview in this widget's local coordinates.
  final void Function(WallMinutes start, WallMinutes end, Rect localBarRect)
      onCreateRange;
  final void Function(Task task)? onTapTask;
  final void Function(Task task, PlacedBar bar)? onSecondaryTapBar;
  final VoidCallback? onSecondaryTapEmpty;

  /// Live snapped time while create/move/resize is active; `null` when idle.
  final void Function(WallMinutes? time)? onDragTime;

  /// When false, pointer on a bar does not start move/resize (create still works).
  final bool allowBarDrag;

  @override
  State<DayGanttGestures> createState() => _DayGanttGesturesState();
}

class _DayGanttGesturesState extends State<DayGanttGestures> {
  static const double _edgeSlop = 8;
  /// Interior edge zone — Windows clamps the pointer at the window border, so
  /// we cannot rely on rawX < 0 / rawX > width alone.
  static const double _edgeZone = 56;
  static const Duration _longPressCreate = Duration(milliseconds: 350);
  static const Duration _edgeRepeatEvery = Duration(milliseconds: 180);

  _DragMode _mode = _DragMode.none;
  Task? _dragTask;
  int _dragLane = 0;
  double _anchorX = 0;
  double _currentX = 0;
  double _createY = 0;
  double _grabOffsetX = 0;
  double _lastRawX = 0;

  int? _activePointer;
  Offset _downPos = Offset.zero;
  Timer? _longPressTimer;
  Timer? _edgeRepeatTimer;
  ScrollHoldController? _scrollHold;

  /// Overscroll ladder: base edge time when the finger first enters the zone.
  WallMinutes? _rightEdgeBase;
  double? _rightHourPx;
  double _rightPushPx = 0;
  WallMinutes? _leftEdgeBase;
  double? _leftHourPx;
  double _leftPushPx = 0;

  void _resetEdgeLadder() {
    _rightEdgeBase = null;
    _rightHourPx = null;
    _rightPushPx = 0;
    _leftEdgeBase = null;
    _leftHourPx = null;
    _leftPushPx = 0;
    _edgeRepeatTimer?.cancel();
    _edgeRepeatTimer = null;
  }

  void _updateEdgePush(double rawX, double dx) {
    final w = widget.geo.widthPx;
    final nearRight = rawX >= w - _edgeZone;
    final nearLeft = rawX <= _edgeZone;

    if (nearRight) {
      _rightEdgeBase ??= widget.geo.viewEnd;
      _rightHourPx ??= hourWidthPx(widget.geo);
      // Depth into the zone + outward drag deltas (and true overscroll).
      final depth = rawX - (w - _edgeZone);
      if (dx > 0) _rightPushPx += dx;
      _rightPushPx = math.max(_rightPushPx, depth);
      if (rawX > w) {
        _rightPushPx = math.max(_rightPushPx, rawX - w + _edgeZone);
      }
    } else if (rawX < w - _edgeZone * 1.5) {
      _rightEdgeBase = null;
      _rightHourPx = null;
      _rightPushPx = 0;
    }

    if (nearLeft) {
      _leftEdgeBase ??= widget.geo.viewStart;
      _leftHourPx ??= hourWidthPx(widget.geo);
      final depth = _edgeZone - rawX;
      if (dx < 0) _leftPushPx += -dx;
      _leftPushPx = math.max(_leftPushPx, depth);
      if (rawX < 0) {
        _leftPushPx = math.max(_leftPushPx, -rawX + _edgeZone);
      }
    } else if (rawX > _edgeZone * 1.5) {
      _leftEdgeBase = null;
      _leftHourPx = null;
      _leftPushPx = 0;
    }

    _syncEdgeRepeat(nearLeft: nearLeft, nearRight: nearRight);
  }

  void _syncEdgeRepeat({required bool nearLeft, required bool nearRight}) {
    final want = nearLeft || nearRight;
    if (!want) {
      _edgeRepeatTimer?.cancel();
      _edgeRepeatTimer = null;
      return;
    }
    _edgeRepeatTimer ??= Timer.periodic(_edgeRepeatEvery, (_) {
      if (!mounted || _mode == _DragMode.none) {
        _edgeRepeatTimer?.cancel();
        _edgeRepeatTimer = null;
        return;
      }
      final w = widget.geo.widthPx;
      final step = (_rightHourPx ?? _leftHourPx ?? hourWidthPx(widget.geo))
          .clamp(28.0, 400.0);
      // Held against the window chrome: keep opening hours gradually.
      if (_lastRawX >= w - _edgeZone * 0.35) {
        _rightEdgeBase ??= widget.geo.viewEnd;
        _rightHourPx ??= hourWidthPx(widget.geo);
        _rightPushPx += step;
        _reportDragTime(_lastRawX);
      } else if (_lastRawX <= _edgeZone * 0.35) {
        _leftEdgeBase ??= widget.geo.viewStart;
        _leftHourPx ??= hourWidthPx(widget.geo);
        _leftPushPx += step;
        _reportDragTime(_lastRawX);
      }
    });
  }

  WallMinutes _expandProbe(double rawX) {
    final geo = widget.geo;
    final bounds = dayBoundsOf(geo);

    if (_rightPushPx > 0 && _rightEdgeBase != null) {
      return expandProbeFromOverscroll(
        day0: bounds.day0,
        maxEnd: bounds.maxEnd,
        edgeBase: _rightEdgeBase!,
        hourPx: _rightHourPx ?? hourWidthPx(geo),
        overscrollPx: _rightPushPx,
        toTheRight: true,
      );
    }
    if (_leftPushPx > 0 && _leftEdgeBase != null) {
      return expandProbeFromOverscroll(
        day0: bounds.day0,
        maxEnd: bounds.maxEnd,
        edgeBase: _leftEdgeBase!,
        hourPx: _leftHourPx ?? hourWidthPx(geo),
        overscrollPx: _leftPushPx,
        toTheRight: false,
      );
    }
    return clampTimeToAxis(geo.timeOf(rawX), bounds.day0);
  }

  PlacedBar? _barAt(Offset pos) {
    for (final bar in widget.bars.reversed) {
      final top = DayGanttLayout.headerHeight +
          bar.lane * DayGanttLayout.laneHeight +
          DayGanttLayout.barGap;
      final height = DayGanttLayout.barHeight;
      if (bar.actualX != null && bar.actualWidth != null) {
        final actualHeight = height * 0.28;
        final actualRect = Rect.fromLTWH(
          bar.actualX! - _edgeSlop,
          top + height - actualHeight + 2,
          bar.actualWidth! + 2 * _edgeSlop,
          actualHeight,
        );
        if (actualRect.contains(pos)) return bar;
      }
      final rect = Rect.fromLTWH(
        bar.x - _edgeSlop,
        top,
        bar.width + 2 * _edgeSlop,
        height,
      );
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

  void _lockScroll() {
    if (_scrollHold != null) return;
    final scrollable = Scrollable.maybeOf(context);
    _scrollHold = scrollable?.position.hold(() {});
  }

  void _unlockScroll() {
    _scrollHold?.cancel();
    _scrollHold = null;
  }

  void _cancelLongPress() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
  }

  void _beginBarDrag(PlacedBar bar, Offset pos) {
    final task = _taskOf(bar);
    if (task == null || task.isDone) return;
    _lockScroll();
    setState(() {
      _dragTask = task;
      _dragLane = bar.lane;
      if ((pos.dx - bar.x).abs() <= _edgeSlop) {
        _mode = _DragMode.resizeStart;
      } else if ((pos.dx - (bar.x + bar.width)).abs() <= _edgeSlop) {
        _mode = _DragMode.resizeEnd;
      } else {
        _mode = _DragMode.move;
        _grabOffsetX = clampXToView(widget.geo, pos.dx);
      }
      _anchorX = clampXToView(widget.geo, pos.dx);
      _currentX = _anchorX;
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons != kPrimaryButton) return;
    _activePointer = e.pointer;
    _downPos = e.localPosition;
    _cancelLongPress();

    final bar = _barAt(e.localPosition);
    if (bar != null && widget.allowBarDrag) {
      _beginBarDrag(bar, e.localPosition);
      return;
    }

    if (e.localPosition.dy > DayGanttLayout.headerHeight) {
      _longPressTimer = Timer(_longPressCreate, () {
        if (!mounted || _activePointer != e.pointer) return;
        _lockScroll();
        setState(() {
          _mode = _DragMode.create;
          _anchorX = clampXToView(widget.geo, _downPos.dx);
          _currentX = _anchorX;
          _createY = _downPos.dy;
        });
        // Seed expand if the long-press starts on an edge.
        _reportDragTime(_currentX);
      });
    }
  }

  @override
  void didUpdateWidget(DayGanttGestures oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_mode == _DragMode.none) return;
    if (oldWidget.geo.viewStart == widget.geo.viewStart &&
        oldWidget.geo.viewEnd == widget.geo.viewEnd &&
        oldWidget.geo.widthPx == widget.geo.widthPx) {
      return;
    }
    final dayAny = widget.geo.viewStart;
    final anchorTime =
        clampTimeToAxis(oldWidget.geo.timeOf(_anchorX), dayAny);
    final currentTime =
        clampTimeToAxis(oldWidget.geo.timeOf(_currentX), dayAny);
    _anchorX = clampXToView(widget.geo, widget.geo.xOf(anchorTime));
    _currentX = clampXToView(widget.geo, widget.geo.xOf(currentTime));
    if (_mode == _DragMode.move) {
      final grabTime =
          clampTimeToAxis(oldWidget.geo.timeOf(_grabOffsetX), dayAny);
      _grabOffsetX = clampXToView(widget.geo, widget.geo.xOf(grabTime));
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_activePointer != e.pointer) return;

    if (_mode == _DragMode.none) {
      if ((e.localPosition - _downPos).distance > kTouchSlop) {
        _cancelLongPress();
      }
      return;
    }

    final rawX = e.localPosition.dx;
    _lastRawX = rawX;
    _updateEdgePush(rawX, e.localDelta.dx);
    final viewX = clampXToView(widget.geo, rawX);
    setState(() => _currentX = viewX);
    _reportDragTime(rawX);
  }

  void _reportDragTime(double rawX) {
    final cb = widget.onDragTime;
    if (cb == null || _mode == _DragMode.none) return;
    switch (_mode) {
      case _DragMode.create:
        cb(_expandProbe(rawX));
      case _DragMode.move:
        final preview = _previewTask();
        if (preview != null) {
          cb(preview.plannedStart);
          cb(preview.plannedEnd);
        }
        if (_rightPushPx > 0 || _leftPushPx > 0) {
          cb(_expandProbe(rawX));
        }
      case _DragMode.resizeStart:
        cb(_expandProbe(rawX));
      case _DragMode.resizeEnd:
        cb(_expandProbe(rawX));
      case _DragMode.none:
        break;
    }
  }

  Future<void> _finishPointer(int pointer) async {
    if (_activePointer != pointer) return;
    _activePointer = null;
    _cancelLongPress();

    final mode = _mode;
    final task = _dragTask;
    final anchor = _anchorX;
    final current = _currentX;
    final grab = _grabOffsetX;
    setState(() {
      _mode = _DragMode.none;
      _dragTask = null;
    });
    _unlockScroll();
    _resetEdgeLadder();
    widget.onDragTime?.call(null);

    switch (mode) {
      case _DragMode.none:
        return;
      case _DragMode.create:
        if ((current - anchor).abs() < 4) return;
        final range = proposeCreate(widget.geo, anchor, current);
        final left = widget.geo.xOf(range.start);
        final width = widget.geo.xOf(range.end) - left;
        final createLane = math.max(
          0,
          ((_createY - DayGanttLayout.headerHeight) /
                  DayGanttLayout.laneHeight)
              .floor(),
        );
        final top = DayGanttLayout.headerHeight +
            createLane * DayGanttLayout.laneHeight +
            DayGanttLayout.barGap;
        final height =
            DayGanttLayout.barHeight;
        widget.onCreateRange(
          range.start,
          range.end,
          Rect.fromLTWH(left, top, math.max(width, 2), height),
        );
      case _DragMode.move:
        await widget
            .onCommitUpdate(proposeMove(task!, widget.geo, current - grab));
      case _DragMode.resizeStart:
        await widget
            .onCommitUpdate(proposeResizeStart(task!, widget.geo, current));
      case _DragMode.resizeEnd:
        await widget
            .onCommitUpdate(proposeResizeEnd(task!, widget.geo, current));
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
  void dispose() {
    _longPressTimer?.cancel();
    _edgeRepeatTimer?.cancel();
    _unlockScroll();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxX = widget.geo.widthPx;

    return LayoutBuilder(builder: (context, constraints) {
      final overlays = <Widget>[];

      if (_mode == _DragMode.create) {
        final range = proposeCreate(widget.geo, _anchorX, _currentX);
        final left = widget.geo.xOf(range.start).clamp(0.0, maxX);
        final right = widget.geo.xOf(range.end).clamp(0.0, maxX);
        final createLane = math.max(
          0,
          ((_createY - DayGanttLayout.headerHeight) /
                  DayGanttLayout.laneHeight)
              .floor(),
        );
        final barTop = DayGanttLayout.headerHeight +
            createLane * DayGanttLayout.laneHeight +
            DayGanttLayout.barGap;
        overlays.add(_previewOverlay(
          theme: theme,
          left: left,
          barTop: barTop,
          width: math.max(right - left, 2),
          label: widget.allowBarDrag
              ? null
              : formatBarTimeLabel(range.start, range.end),
        ));
      }

      final preview = _previewTask();
      if (preview != null) {
        final left = widget.geo.xOf(preview.plannedStart).clamp(0.0, maxX);
        final right = widget.geo.xOf(preview.plannedEnd).clamp(0.0, maxX);
        final barTop = DayGanttLayout.headerHeight +
            _dragLane * DayGanttLayout.laneHeight +
            DayGanttLayout.barGap;
        overlays.add(_previewOverlay(
          theme: theme,
          left: left,
          barTop: barTop,
          width: math.max(right - left, 2),
        ));
      }

      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: (e) => _finishPointer(e.pointer),
        onPointerCancel: (e) => _finishPointer(e.pointer),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTapUp: (d) {
            if (_mode != _DragMode.none) return;
            final bar = _barAt(d.localPosition);
            if (bar != null) {
              final task = _taskOf(bar);
              if (task != null) widget.onTapTask?.call(task);
            }
          },
          onSecondaryTapUp: (d) {
            final bar = _barAt(d.localPosition);
            if (bar == null) {
              widget.onSecondaryTapEmpty?.call();
              return;
            }
            final task = _taskOf(bar);
            if (task != null) widget.onSecondaryTapBar?.call(task, bar);
          },
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [widget.canvas, ...overlays],
          ),
        ),
      );
    });
  }

  Widget _previewOverlay({
    required ThemeData theme,
    required double left,
    required double barTop,
    required double width,
    String? label,
  }) {
    return Positioned(
      left: left,
      top: barTop,
      width: width,
      height: DayGanttLayout.barHeight,
      child: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
          border: Border.all(color: theme.colorScheme.primary, width: 1.5),
        ),
        child: label == null
            ? null
            : Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.clip,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  height: 1.15,
                ),
              ),
      ),
    );
  }
}
