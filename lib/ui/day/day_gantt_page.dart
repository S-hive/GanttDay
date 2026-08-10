import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/gantt/day_segmenter.dart';
import '../../domain/gantt/day_span_clamp.dart';
import '../../domain/gantt/day_visible_range.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/gantt/urgency_palette.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../complete/complete_dialog.dart';
import 'bar_time_label.dart';
import 'create_task_popup.dart';
import 'day_gantt_gestures.dart';
import 'day_gantt_painter.dart';

/// One waterfall row per task that overlaps [geo]'s visible window.
({List<PlacedBar> bars, List<Task> rows}) buildTableRows({
  required List<Task> tasks,
  required Map<String, Tag> tags,
  required GanttGeometry geo,
  required WallMinutes dayAny,
  required WallMinutes now,
  required int urgencyWindowDays,
}) {
  final sorted = [...tasks]..sort((a, b) {
      final c = a.plannedStart.compareTo(b.plannedStart);
      return c != 0 ? c : a.title.compareTo(b.title);
    });

  final bars = <PlacedBar>[];
  final rows = <Task>[];
  for (final task in sorted) {
    // Clip to the fitted axis (may span into following days, ≤7d).
    final plannedSegs = DaySegmenter.clipToRange(
      taskId: task.id,
      start: task.plannedStart,
      end: task.plannedEnd,
      rangeStart: geo.viewStart,
      rangeEnd: geo.viewEnd,
    );
    final hasActual = task.isDone &&
        task.actualStart != null &&
        task.actualEnd != null;
    final actualSegs = hasActual
        ? DaySegmenter.clipToRange(
            taskId: task.id,
            start: task.actualStart!,
            end: task.actualEnd!,
            rangeStart: geo.viewStart,
            rangeEnd: geo.viewEnd,
          )
        : const [];
    // Completed: outer bar = actual, inner strip = planned.
    // Incomplete (or actual off-screen): outer = planned.
    final useActualShell = actualSegs.isNotEmpty;
    if (!useActualShell && plannedSegs.isEmpty) continue;

    final shell = useActualShell ? actualSegs.single : plannedSegs.single;
    final lane = rows.length;
    rows.add(task);
    final swatchId = resolveTaskSwatchId(task, tags);
    final base = kFactoryColorSwatches.firstWhere(
      (s) => s.id == swatchId,
      orElse: () => kFactoryColorSwatches.firstWhere((s) => s.isDefault),
    );
    final paint = UrgencyPalette.paint(
      base: base,
      plannedStart: task.plannedStart,
      plannedEnd: task.plannedEnd,
      now: now,
      isDone: task.isDone,
      actualStart: task.actualStart,
      actualEnd: task.actualEnd,
      urgencyWindowDays: urgencyWindowDays,
    );

    double? innerX;
    double? innerWidth;
    BarPaint? innerPaint;
    if (useActualShell && plannedSegs.isNotEmpty) {
      final p = plannedSegs.single;
      innerX = geo.xOf(p.start);
      innerWidth = geo.xOf(p.end) - geo.xOf(p.start);
      innerPaint = paint.planned;
    }

    final spanStart =
        useActualShell ? task.actualStart! : task.plannedStart;
    final spanEnd = useActualShell ? task.actualEnd! : task.plannedEnd;
    final overnight = spansMultipleCalendarDays(spanStart, spanEnd);
    bars.add(PlacedBar(
      taskId: task.id,
      x: geo.xOf(shell.start),
      width: geo.xOf(shell.end) - geo.xOf(shell.start),
      lane: lane,
      paint: useActualShell
          ? (paint.actual ?? paint.planned)
          : paint.planned,
      title: task.title,
      isDone: task.isDone,
      spanStart: spanStart,
      spanEnd: spanEnd,
      notes: task.notes,
      // Overnight / multi-day stubs may be short; allow caption overflow.
      overflowCaption: overnight,
      actualX: innerX,
      actualWidth: innerWidth,
      actualPaint: innerPaint,
    ));
  }
  return (bars: bars, rows: rows);
}

/// Back-compat helper used by older call sites / tests.
List<PlacedBar> buildPlacedBars({
  required List<Task> tasks,
  required Map<String, Tag> tags,
  required GanttGeometry geo,
  required WallMinutes dayAny,
  required WallMinutes now,
  required int urgencyWindowDays,
}) {
  return buildTableRows(
    tasks: tasks,
    tags: tags,
    geo: geo,
    dayAny: dayAny,
    now: now,
    urgencyWindowDays: urgencyWindowDays,
  ).bars;
}

class DayGanttPage extends StatefulWidget {
  const DayGanttPage({
    super.key,
    required this.services,
    required this.date,
    this.onBarTap,
    this.interactive = true,
    this.filterTagIds = const {},
  });

  final AppServices services;
  final DateTime date;
  final void Function(Task task)? onBarTap;
  final bool interactive;
  final Set<String> filterTagIds;

  @override
  State<DayGanttPage> createState() => _DayGanttPageState();
}

class _DayGanttPageState extends State<DayGanttPage> {
  static const double _minZoom = 0.5;
  static const double _maxZoom = 4.0;

  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<AppSettings>? _settingsSub;
  Timer? _nowTimer;
  final ScrollController _hScroll = ScrollController();
  final GlobalKey _ganttKey = GlobalKey();

  /// 1.0 = fitted hour window fills the viewport width.
  double _zoom = 1.0;

  /// Live drag probes during an active gesture.
  WallMinutes? _dragProbeMin;
  WallMinutes? _dragProbeMax;

  /// Sticky axis expansion from edge-drag (survives gesture end / task save).
  int? _stickyStartMin;
  int? _stickyEndMin;

  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};
  Map<String, List<String>> _taskTagIds = const {};
  AppSettings _settings = const AppSettings();

  WallMinutes get _day0 => WallClock.minutes(
      DateTime(widget.date.year, widget.date.month, widget.date.day));

  Iterable<WallMinutes> get _dragProbes sync* {
    if (_dragProbeMin != null) yield _dragProbeMin!;
    if (_dragProbeMax != null && _dragProbeMax != _dragProbeMin) {
      yield _dragProbeMax!;
    }
  }

  void _clearDragProbes() {
    _dragProbeMin = null;
    _dragProbeMax = null;
  }

  void _clearStickyFit() {
    _stickyStartMin = null;
    _stickyEndMin = null;
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
    _settingsSub = widget.services.settings.watch().listen((s) {
      if (!mounted) return;
      final hoursChanged = s.visibleStartHour != _settings.visibleStartHour ||
          s.visibleEndHour != _settings.visibleEndHour;
      setState(() {
        _settings = s;
        if (hoursChanged) {
          _zoom = 1.0;
          _clearDragProbes();
          _clearStickyFit();
        }
      });
    });
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(DayGanttPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _zoom = 1.0;
      _clearDragProbes();
      _clearStickyFit();
      _subscribe();
    }
  }

  List<Task> get _visibleTasks {
    if (widget.filterTagIds.isEmpty) return _tasks;
    return _tasks.where((t) {
      final ids = _taskTagIds[t.id] ?? const <String>[];
      return ids.any(widget.filterTagIds.contains) ||
          (t.primaryTagId != null &&
              widget.filterTagIds.contains(t.primaryTagId));
    }).toList();
  }

  ({int start, int end}) _fitFor(
    List<Task> tasks, {
    Iterable<WallMinutes> dragTimes = const [],
  }) {
    final day1 = _day0 + WallClock.minutesPerDay;
    // Auto-fit only from tasks that touch the selected day — not the whole
    // 7-day window (that was densifying the entire week on open).
    final spans = <({WallMinutes start, WallMinutes end})>[];
    for (final task in tasks) {
      if (task.plannedEnd <= _day0 || task.plannedStart >= day1) continue;
      // Fit only the selected day's portion — multi-day growth is gesture /
      // sticky only, so the axis snaps back to "today" after create.
      for (final seg in DaySegmenter.segmentsForDay(task, _day0)) {
        spans.add((start: seg.start, end: seg.end));
      }
    }
    final computed = computeDayFitMinutes(
      settingsStartHour: _settings.visibleStartHour,
      settingsEndHour: _settings.visibleEndHour,
      day0: _day0,
      daySpans: spans,
      alsoInclude: dragTimes,
    );
    var start = computed.start;
    var end = computed.end;
    if (_stickyStartMin != null) {
      start = math.min(start, _stickyStartMin!);
    }
    if (_stickyEndMin != null) {
      end = math.max(end, _stickyEndMin!);
    }
    return (start: start, end: end);
  }

  void _onDragTime(WallMinutes? time, GanttGeometry geo, double viewportW) {
    if (time == null) {
      if (_dragProbeMin == null && _dragProbeMax == null) return;
      // Keep sticky expansion through the create popup; cleared when create ends.
      setState(_clearDragProbes);
      return;
    }

    final clampedTime = clampTimeToAxis(time, _day0);
    final tasks = _visibleTasks;
    final before = _fitFor(tasks, dragTimes: _dragProbes);
    final nextMin = _dragProbeMin == null
        ? clampedTime
        : math.min(_dragProbeMin!, clampedTime);
    final nextMax = _dragProbeMax == null
        ? clampedTime
        : math.max(_dragProbeMax!, clampedTime);
    final after = _fitFor(tasks, dragTimes: [nextMin, nextMax]);

    if (after.start == before.start &&
        after.end == before.end &&
        nextMin == _dragProbeMin &&
        nextMax == _dragProbeMax) {
      return;
    }

    final anchorTime = _hScroll.hasClients
        ? geo.timeOf(_hScroll.offset + viewportW / 2)
        : clampedTime;

    setState(() {
      _dragProbeMin = nextMin;
      _dragProbeMax = nextMax;
      _stickyStartMin = after.start;
      _stickyEndMin = after.end;
    });

    if (after.start == before.start && after.end == before.end) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hScroll.hasClients) return;
      final newGeo = GanttGeometry(
        viewStart: _day0 + after.start,
        viewEnd: _day0 + after.end,
        widthPx: viewportW * _zoom,
      );
      final max = _hScroll.position.maxScrollExtent;
      _hScroll.jumpTo(
        (newGeo.xOf(anchorTime) - viewportW / 2).clamp(0.0, max),
      );
    });
  }

  void _onPointerScroll(PointerScrollEvent e, GanttGeometry geo, double viewportW) {
    // Claim the signal so nested ScrollViews do not also consume it.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      if (event is! PointerScrollEvent || !_hScroll.hasClients) return;

      final ctrl = HardwareKeyboard.instance.isControlPressed;
      if (ctrl) {
        final oldZoom = _zoom;
        final factor = event.scrollDelta.dy > 0 ? 1 / 1.1 : 1.1;
        final newZoom = (_zoom * factor).clamp(_minZoom, _maxZoom);
        if (newZoom == oldZoom) return;

        final centerPx = _hScroll.offset + viewportW / 2;
        final centerTime = geo.timeOf(centerPx);
        setState(() => _zoom = newZoom);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_hScroll.hasClients) return;
          final newGeo = GanttGeometry(
            viewStart: geo.viewStart,
            viewEnd: geo.viewEnd,
            widthPx: viewportW * _zoom,
          );
          final newCenterX = newGeo.xOf(centerTime);
          final maxExtent = _hScroll.position.maxScrollExtent;
          _hScroll.jumpTo((newCenterX - viewportW / 2).clamp(0.0, maxExtent));
        });
        return;
      }

      // Wheel / trackpad → pan the timeline horizontally.
      final dx =
          event.scrollDelta.dx != 0 ? event.scrollDelta.dx : event.scrollDelta.dy;
      final next = (_hScroll.offset + dx)
          .clamp(0.0, _hScroll.position.maxScrollExtent);
      _hScroll.jumpTo(next);
    });
  }

  void _subscribe() {
    _tasksSub?.cancel();
    _tasksSub = widget.services.tasks
        .watchTasksOverlapping(_day0, _day0 + kDayViewMaxSpanMinutes)
        .listen((tasks) async {
      final tags = await widget.services.tasks.listTags();
      final tagIds = <String, List<String>>{};
      for (final t in tasks) {
        tagIds[t.id] = await widget.services.tasks.tagIdsForTask(t.id);
      }
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _tags = {for (final t in tags) t.id: t};
        _taskTagIds = tagIds;
      });
    });
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    _settingsSub?.cancel();
    _nowTimer?.cancel();
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _commitUpdate(Task updated) async {
    final clamped = clampSpanToAxis(
      start: updated.plannedStart,
      end: updated.plannedEnd,
      dayAny: _day0,
    );
    final safe = updated.copyWith(
      plannedStart: clamped.start,
      plannedEnd: clamped.end,
    );
    try {
      await widget.services.tasks.upsert(safe);
    } catch (e) {
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败，已恢复原位置：$e')),
      );
    }
  }

  Future<void> _setActualTime(Task task) async {
    final result = await showCompleteDialog(context, task: task);
    if (result == null || !mounted) return;
    try {
      await widget.services.tasks.complete(
        task.id,
        actualStart: result.start,
        actualEnd: result.end,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('设置实际时间失败：$e')),
      );
    }
  }

  Future<void> _createFromRange(
    WallMinutes start,
    WallMinutes end,
    Rect localBarRect,
  ) async {
    final box = _ganttKey.currentContext?.findRenderObject() as RenderBox?;
    final anchorGlobal = box != null
        ? Rect.fromPoints(
            box.localToGlobal(localBarRect.topLeft),
            box.localToGlobal(localBarRect.bottomRight),
          )
        : localBarRect;

    final title = await showCreateTaskPopup(
      context: context,
      anchorGlobal: anchorGlobal,
      start: start,
      end: end,
    );
    // After create (or cancel), restore today's default fit window.
    if (mounted) {
      setState(() {
        _clearStickyFit();
        _clearDragProbes();
        _zoom = 1.0;
      });
      if (_hScroll.hasClients) {
        _hScroll.jumpTo(0);
      }
    }
    if (title == null || title.trim().isEmpty) return;
    final clamped = clampSpanToAxis(start: start, end: end, dayAny: _day0);
    final task = Task(
      id: const Uuid().v4(),
      title: title.trim(),
      plannedStart: clamped.start,
      plannedEnd: clamped.end,
      autoSwatchId: kDefaultSwatchId,
      createdAt: WallClock.now(),
    );
    try {
      await widget.services.tasks.upsert(task);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('创建失败：$e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final timelineViewport = math.max(constraints.maxWidth, 120.0);
      final visibleTasks = _visibleTasks;
      final fit = _fitFor(visibleTasks, dragTimes: _dragProbes);
      final startMin = fit.start;
      final endMin = fit.end;
      // Fitted window (settings ∪ tasks ∪ live drag) fills the viewport at
      // zoom=1. Right edge may grow past midnight up to 7 days.
      final totalWidth = timelineViewport * _zoom;
      final viewStart = _day0 + startMin;
      final viewEnd = _day0 + endMin;
      final geo = GanttGeometry(
        viewStart: viewStart,
        viewEnd: viewEnd,
        widthPx: totalWidth,
      );

      final now = WallClock.now();
      final table = buildTableRows(
        tasks: visibleTasks,
        tags: _tags,
        geo: geo,
        dayAny: _day0,
        now: now,
        urgencyWindowDays: _settings.urgencyWindowDays,
      );
      final rows = table.rows;
      final bars = table.bars;
      final rowCount = math.max(rows.length, 1);
      final contentHeight = DayGanttLayout.headerHeight +
          rowCount * DayGanttLayout.laneHeight;

      final pageDay = WallClock.dateTime(_day0);
      final hourMarks = <HourMark>[];
      for (var m = startMin; m <= endMin; m += 60) {
        final t = _day0 + m;
        final dt = WallClock.dateTime(t);
        final otherDay = dt.day != pageDay.day ||
            dt.month != pageDay.month ||
            dt.year != pageDay.year;
        final midnightMark = m > 0 && otherDay && dt.hour == 0;
        hourMarks.add(HourMark(
          x: geo.xOf(t),
          label: midnightMark ? '${dt.month}/${dt.day}' : '${dt.hour}:00',
          emphasized: m == startMin ||
              m == endMin ||
              midnightMark ||
              dt.hour % 6 == 0,
          isDayBoundary: midnightMark,
        ));
      }

      final nowInView = now >= viewStart && now <= viewEnd;

      final hScroll = Scrollbar(
        controller: _hScroll,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        child: SingleChildScrollView(
          controller: _hScroll,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: totalWidth,
            height: math.max(contentHeight, constraints.maxHeight),
            // Rebuild captions as the viewport scrolls (sticky labels).
            child: ListenableBuilder(
              listenable: _hScroll,
              builder: (context, _) {
                final viewportLeft =
                    _hScroll.hasClients ? _hScroll.offset : 0.0;
                Widget canvas = CustomPaint(
                  size: Size(totalWidth, contentHeight),
                  painter: DayGanttPainter(
                    bars: bars,
                    hourMarks: hourMarks,
                    rowCount: rowCount,
                    todayLineX: nowInView ? geo.xOf(now) : null,
                    viewportLeft: viewportLeft,
                    viewportWidth: timelineViewport,
                  ),
                );

                if (widget.interactive) {
                  canvas = DayGanttGestures(
                    key: _ganttKey,
                    canvas: canvas,
                    geo: geo,
                    bars: bars,
                    tasks: rows,
                    onCommitUpdate: _commitUpdate,
                    onCreateRange: _createFromRange,
                    onTapTask: widget.onBarTap,
                    onSecondaryTapTask: _setActualTime,
                    onDragTime: (time) =>
                        _onDragTime(time, geo, timelineViewport),
                  );
                } else if (widget.onBarTap != null) {
                  canvas = GestureDetector(
                    onTapUp: (d) {
                      final task = hitTestBar(bars, rows, d.localPosition);
                      if (task != null) widget.onBarTap!(task);
                    },
                    child: canvas,
                  );
                }
                return canvas;
              },
            ),
          ),
        ),
      );

      return Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent) {
            _onPointerScroll(signal, geo, timelineViewport);
          }
        },
        child: SingleChildScrollView(
          child: SizedBox(
            height: math.max(contentHeight, constraints.maxHeight),
            child: hScroll,
          ),
        ),
      );
    });
  }
}

Task? hitTestBar(List<PlacedBar> bars, List<Task> tasks, Offset position) {
  for (final bar in bars) {
    final top = DayGanttLayout.headerHeight +
        bar.lane * DayGanttLayout.laneHeight +
        DayGanttLayout.barGap;
    final rect = Rect.fromLTWH(bar.x, top, bar.width,
        DayGanttLayout.barHeight);
    if (rect.contains(position)) {
      for (final t in tasks) {
        if (t.id == bar.taskId) return t;
      }
    }
  }
  return null;
}
