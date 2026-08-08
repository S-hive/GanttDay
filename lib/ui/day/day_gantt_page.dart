import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/gantt/auto_hue.dart';
import '../../domain/gantt/day_segmenter.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/gantt/lane_layout.dart';
import '../../domain/gantt/urgency_palette.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/gantt_segment.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import 'day_gantt_gestures.dart';
import 'day_gantt_painter.dart';

/// Maps tasks to fully placed bars: segments -> lanes -> colors -> pixels.
/// Pure function so it can be unit-tested and reused by the week view.
List<PlacedBar> buildPlacedBars({
  required List<Task> tasks,
  required Map<String, Tag> tags,
  required GanttGeometry geo,
  required WallMinutes dayAny,
  required WallMinutes now,
  required int urgencyWindowDays,
}) {
  final segments = <GanttSegment>[];
  final taskById = <String, Task>{};
  for (final task in tasks) {
    taskById[task.id] = task;
    segments.addAll(DaySegmenter.segmentsForDay(task, dayAny));
  }
  final lanes = LaneLayout.assign(segments);

  final bars = <PlacedBar>[];
  for (final seg in segments) {
    final task = taskById[seg.taskId]!;
    final baseHue =
        task.overrideHue ?? tags[task.primaryTagId]?.hue ?? task.autoHue;
    final paint = UrgencyPalette.paint(
      baseHue: baseHue,
      plannedStart: task.plannedStart,
      plannedEnd: task.plannedEnd,
      now: now,
      isDone: task.isDone,
      actualStart: task.actualStart,
      actualEnd: task.actualEnd,
      urgencyWindowDays: urgencyWindowDays,
    );

    double? actualX;
    double? actualWidth;
    if (task.isDone && task.actualStart != null && task.actualEnd != null) {
      final actualSegs = DaySegmenter.clipToDay(
        taskId: task.id,
        start: task.actualStart!,
        end: task.actualEnd!,
        dayAny: dayAny,
      );
      if (actualSegs.isNotEmpty) {
        final a = actualSegs.single;
        actualX = geo.xOf(a.start);
        actualWidth = geo.xOf(a.end) - geo.xOf(a.start);
      }
    }

    bars.add(PlacedBar(
      taskId: task.id,
      x: geo.xOf(seg.start),
      width: geo.xOf(seg.end) - geo.xOf(seg.start),
      lane: lanes[LaneLayout.keyOf(seg)]!,
      paint: paint.planned,
      title: task.title,
      isDone: task.isDone,
      actualX: actualX,
      actualWidth: actualWidth,
      actualPaint: paint.actual,
    ));
  }
  return bars;
}

class DayGanttPage extends StatefulWidget {
  const DayGanttPage({
    super.key,
    required this.services,
    required this.date,
    this.onBarTap,
    this.interactive = true,
  });

  final AppServices services;
  final DateTime date;
  final void Function(Task task)? onBarTap;
  final bool interactive;

  @override
  State<DayGanttPage> createState() => _DayGanttPageState();
}

class _DayGanttPageState extends State<DayGanttPage> {
  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<AppSettings>? _settingsSub;
  Timer? _nowTimer;
  final ScrollController _scroll = ScrollController();
  bool _didInitialScroll = false;

  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};
  AppSettings _settings = const AppSettings();

  WallMinutes get _day0 => WallClock.minutes(
      DateTime(widget.date.year, widget.date.month, widget.date.day));

  @override
  void initState() {
    super.initState();
    _subscribe();
    _settingsSub = widget.services.settings.watch().listen((s) {
      if (mounted) setState(() => _settings = s);
    });
    _nowTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(DayGanttPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) {
      _didInitialScroll = false;
      _subscribe();
    }
  }

  void _subscribe() {
    _tasksSub?.cancel();
    _tasksSub = widget.services.tasks
        .watchTasksOverlapping(_day0, _day0 + WallClock.minutesPerDay)
        .listen((tasks) async {
      final tags = await widget.services.tasks.listTags();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _tags = {for (final t in tags) t.id: t};
      });
    });
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    _settingsSub?.cancel();
    _nowTimer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return widget.date.year == now.year &&
        widget.date.month == now.month &&
        widget.date.day == now.day;
  }

  /// Persist a moved/resized task. On failure the stream re-emits the stored
  /// state, so the bar visually snaps back — never fake success (spec §8).
  Future<void> _commitUpdate(Task updated) async {
    try {
      await widget.services.tasks.upsert(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {}); // repaint from unchanged _tasks: bar snaps back
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败，已恢复原位置：$e')),
      );
    }
  }

  Future<void> _createFromRange(WallMinutes start, WallMinutes end) async {
    final title = await _promptTitle();
    if (title == null || title.trim().isEmpty) return;
    final tags = await widget.services.tasks.listTags();
    final task = Task(
      id: const Uuid().v4(),
      title: title.trim(),
      plannedStart: start,
      plannedEnd: end,
      autoHue: pickAutoHue([for (final t in tags) t.hue]),
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

  Future<String?> _promptTitle() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新任务'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '任务名'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final visibleHours =
          (_settings.visibleEndHour - _settings.visibleStartHour).clamp(1, 24);
      final hourWidth = constraints.maxWidth / visibleHours;
      final totalWidth = hourWidth * 24;
      final geo = GanttGeometry(
        viewStart: _day0,
        viewEnd: _day0 + WallClock.minutesPerDay,
        widthPx: totalWidth,
      );

      final now = WallClock.now();
      final bars = buildPlacedBars(
        tasks: _tasks,
        tags: _tags,
        geo: geo,
        dayAny: _day0,
        now: now,
        urgencyWindowDays: _settings.urgencyWindowDays,
      );

      final laneCount = bars.isEmpty
          ? 1
          : bars.map((b) => b.lane).reduce((a, b) => a > b ? a : b) + 1;
      final contentHeight = DayGanttLayout.headerHeight +
          laneCount * DayGanttLayout.laneHeight +
          DayGanttLayout.laneHeight;

      final hourMarks = [
        for (var h = 0; h <= 24; h++)
          HourMark(
            x: geo.xOf(_day0 + h * 60),
            label: h == 24 ? '' : '$h:00',
            emphasized: h == 0 || h == 24,
          ),
      ];

      if (!_didInitialScroll) {
        _didInitialScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            _scroll.jumpTo(geo.xOf(_day0 + _settings.visibleStartHour * 60));
          }
        });
      }

      Widget canvas = CustomPaint(
        size: Size(totalWidth, contentHeight),
        painter: DayGanttPainter(
          bars: bars,
          hourMarks: hourMarks,
          todayLineX: _isToday ? geo.xOf(now) : null,
        ),
      );

      if (widget.interactive) {
        canvas = DayGanttGestures(
          canvas: canvas,
          geo: geo,
          bars: bars,
          tasks: _tasks,
          onCommitUpdate: _commitUpdate,
          onCreateRange: _createFromRange,
          onTapTask: widget.onBarTap,
        );
      } else if (widget.onBarTap != null) {
        canvas = GestureDetector(
          onTapUp: (d) {
            final task = hitTestBar(bars, _tasks, d.localPosition);
            if (task != null) widget.onBarTap!(task);
          },
          child: canvas,
        );
      }

      return SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: totalWidth,
          height: math.max(contentHeight, constraints.maxHeight),
          child: Align(alignment: Alignment.topLeft, child: canvas),
        ),
      );
    });
  }
}

/// Finds the task whose bar contains [position], or null.
Task? hitTestBar(List<PlacedBar> bars, List<Task> tasks, Offset position) {
  for (final bar in bars) {
    final top = DayGanttLayout.headerHeight +
        bar.lane * DayGanttLayout.laneHeight +
        DayGanttLayout.barGap;
    final rect = Rect.fromLTWH(bar.x, top, bar.width,
        DayGanttLayout.laneHeight - 2 * DayGanttLayout.barGap);
    if (rect.contains(position)) {
      for (final t in tasks) {
        if (t.id == bar.taskId) return t;
      }
    }
  }
  return null;
}
