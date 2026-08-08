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
import '../day/day_gantt_gestures.dart';
import '../day/day_gantt_painter.dart';
import '../task/task_form_page.dart';

/// Week view: same horizontal Gantt as day, spanning 7 days. Default viewport
/// is about two days wide; day boundaries are emphasized (spec section 3).
class WeekGanttPage extends StatefulWidget {
  const WeekGanttPage({
    super.key,
    required this.services,
    required this.anchorDate,
    this.filterTagIds = const {},
  });

  final AppServices services;
  final DateTime anchorDate;
  final Set<String> filterTagIds;

  @override
  State<WeekGanttPage> createState() => _WeekGanttPageState();
}

class _WeekGanttPageState extends State<WeekGanttPage> {
  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<AppSettings>? _settingsSub;
  final ScrollController _scroll = ScrollController();
  bool _didInitialScroll = false;

  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};
  AppSettings _settings = const AppSettings();

  /// Monday of the week containing [anchorDate].
  DateTime get _weekStart {
    final d = DateTime(
        widget.anchorDate.year, widget.anchorDate.month, widget.anchorDate.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  WallMinutes get _rangeStart => WallClock.minutes(_weekStart);
  WallMinutes get _rangeEnd => _rangeStart + 7 * WallClock.minutesPerDay;

  @override
  void initState() {
    super.initState();
    _subscribe();
    _settingsSub = widget.services.settings.watch().listen((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  @override
  void didUpdateWidget(WeekGanttPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchorDate != widget.anchorDate ||
        oldWidget.filterTagIds != widget.filterTagIds) {
      _didInitialScroll = false;
      _subscribe();
    }
  }

  void _subscribe() {
    _tasksSub?.cancel();
    _tasksSub = widget.services.tasks
        .watchTasksOverlapping(_rangeStart, _rangeEnd)
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
    _scroll.dispose();
    super.dispose();
  }

  List<Task> get _filtered {
    if (widget.filterTagIds.isEmpty) return _tasks;
    return _tasks
        .where((t) =>
            t.primaryTagId != null &&
            widget.filterTagIds.contains(t.primaryTagId))
        .toList();
  }

  Future<void> _commitUpdate(Task updated) async {
    try {
      await widget.services.tasks.upsert(updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存失败，已恢复原位置：$e')),
      );
    }
  }

  Future<void> _createFromRange(WallMinutes start, WallMinutes end) async {
    final controller = TextEditingController();
    final title = await showDialog<String>(
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
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('创建')),
        ],
      ),
    );
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
    await widget.services.tasks.upsert(task);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      // ~2 days visible by default.
      final twoDayWidth = constraints.maxWidth;
      final totalWidth = twoDayWidth * 7 / 2;
      final geo = GanttGeometry(
        viewStart: _rangeStart,
        viewEnd: _rangeEnd,
        widthPx: totalWidth,
      );

      final now = WallClock.now();
      final segments = <GanttSegment>[];
      final taskById = {for (final t in _filtered) t.id: t};
      for (final task in _filtered) {
        for (var d = 0; d < 7; d++) {
          final dayAny = _rangeStart + d * WallClock.minutesPerDay;
          segments.addAll(DaySegmenter.segmentsForDay(task, dayAny));
        }
      }
      final lanes = LaneLayout.assign(segments);
      final bars = <PlacedBar>[];
      for (final seg in segments) {
        final task = taskById[seg.taskId]!;
        final baseHue =
            task.overrideHue ?? _tags[task.primaryTagId]?.hue ?? task.autoHue;
        final paint = UrgencyPalette.paint(
          baseHue: baseHue,
          plannedStart: task.plannedStart,
          plannedEnd: task.plannedEnd,
          now: now,
          isDone: task.isDone,
          actualStart: task.actualStart,
          actualEnd: task.actualEnd,
          urgencyWindowDays: _settings.urgencyWindowDays,
        );
        double? actualX;
        double? actualWidth;
        if (task.isDone &&
            task.actualStart != null &&
            task.actualEnd != null) {
          // Clip actual to the same day as this planned segment.
          final dayAny = WallClock.dayStart(seg.start);
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

      final laneCount = bars.isEmpty
          ? 1
          : bars.map((b) => b.lane).reduce((a, b) => a > b ? a : b) + 1;
      final contentHeight = DayGanttLayout.headerHeight +
          laneCount * DayGanttLayout.laneHeight +
          DayGanttLayout.laneHeight;

      final hourMarks = <HourMark>[];
      for (var d = 0; d < 7; d++) {
        final day0 = _rangeStart + d * WallClock.minutesPerDay;
        final dayDt = WallClock.dateTime(day0);
        for (var h = 0; h < 24; h++) {
          hourMarks.add(HourMark(
            x: geo.xOf(day0 + h * 60),
            label: h == 0
                ? '${dayDt.month}/${dayDt.day}'
                : (h % 6 == 0 ? '$h:00' : ''),
            emphasized: h == 0,
          ));
        }
      }
      hourMarks.add(HourMark(
        x: geo.xOf(_rangeEnd),
        label: '',
        emphasized: true,
      ));

      if (!_didInitialScroll) {
        _didInitialScroll = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) {
            // Prefer today's day within the week, else week start.
            final today = DateTime.now();
            final today0 = DateTime(today.year, today.month, today.day);
            final offsetDays = today0.difference(_weekStart).inDays;
            final jumpDay = (offsetDays >= 0 && offsetDays < 7) ? offsetDays : 0;
            _scroll.jumpTo(
              geo.xOf(_rangeStart +
                  jumpDay * WallClock.minutesPerDay +
                  _settings.visibleStartHour * 60),
            );
          }
        });
      }

      final todayLine = (() {
        final n = DateTime.now();
        final n0 = DateTime(n.year, n.month, n.day);
        if (n0.isBefore(_weekStart) ||
            !n0.isBefore(_weekStart.add(const Duration(days: 7)))) {
          return null;
        }
        return geo.xOf(now);
      })();

      Widget canvas = CustomPaint(
        size: Size(totalWidth, contentHeight),
        painter: DayGanttPainter(
          bars: bars,
          hourMarks: hourMarks,
          todayLineX: todayLine,
        ),
      );

      canvas = DayGanttGestures(
        canvas: canvas,
        geo: geo,
        bars: bars,
        tasks: _filtered,
        onCommitUpdate: _commitUpdate,
        onCreateRange: _createFromRange,
        onTapTask: (task) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => TaskFormPage(
              services: widget.services,
              existing: task,
            ),
          ));
        },
      );

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
