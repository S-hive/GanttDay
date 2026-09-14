import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../domain/gantt/argb_color.dart';
import '../../domain/gantt/paint_resolve.dart';
import '../../domain/gantt/tag_filter.dart';
import '../../domain/gantt/urgency_palette.dart';
import '../../domain/models/default_color.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../common/bar_detail_tooltip.dart';
import '../day/day_gantt_painter.dart';
import 'month_span_layout.dart';

/// Month grid with week-row spanning colored bars (title only).
class MonthPage extends StatefulWidget {
  const MonthPage({
    super.key,
    required this.services,
    required this.month,
    required this.onOpenDay,
    this.filterTagIds = const {},
  });

  final AppServices services;
  final DateTime month;
  final void Function(DateTime day) onOpenDay;
  final Set<String> filterTagIds;

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  static const double _barHeight = 15;
  static const double _barGap = 2;
  static const double _dayHeaderHeight = 22;
  static const double _minBarWidth = 4;

  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<List<DefaultColor>>? _defaultsSub;
  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};
  int? _currentDefaultArgb;
  int _tasksLoadEpoch = 0;

  DateTime get _monthStart =>
      DateTime(widget.month.year, widget.month.month, 1);

  DateTime get _monthEndExclusive =>
      DateTime(widget.month.year, widget.month.month + 1, 1);

  @override
  void initState() {
    super.initState();
    _subscribe();
    _defaultsSub =
        widget.services.tasks.watchDefaultColors().listen((colors) {
      if (!mounted) return;
      int? current;
      for (final c in colors) {
        if (c.isCurrent) {
          current = c.argb;
          break;
        }
      }
      setState(() => _currentDefaultArgb = current);
    });
  }

  @override
  void didUpdateWidget(MonthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) {
      _subscribe();
    } else if (oldWidget.filterTagIds != widget.filterTagIds) {
      setState(() {});
    }
  }

  void _subscribe() {
    _tasksSub?.cancel();
    _tasksLoadEpoch++;
    final start = WallClock.minutes(_monthStart);
    final end = WallClock.minutes(_monthEndExclusive);
    _tasksSub = widget.services.tasks
        .watchTasksOverlapping(start, end)
        .listen((tasks) async {
      final epoch = ++_tasksLoadEpoch;
      final tags = await widget.services.tasks.listTags();
      if (!mounted || epoch != _tasksLoadEpoch) return;
      setState(() {
        _tasks = tasks;
        _tags = {for (final t in tags) t.id: t};
      });
    });
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
    _defaultsSub?.cancel();
    super.dispose();
  }

  BarPaint _paintFor(Task task) {
    final argb = resolveTaskArgb(
      task,
      _tags,
      currentDefaultArgb: _currentDefaultArgb,
    );
    final hsl = ArgbColor.toHsl(argb);
    final overdue = !task.isDone && task.plannedEnd < WallClock.now();
    if (overdue) {
      return BarPaint(
        hue: hsl.hue.round() % 360,
        saturation: 0.12,
        lightness: 0.55,
        hatchOverdue: false,
        isPlannedGray: true,
      );
    }
    return BarPaint(
      hue: hsl.hue.round() % 360,
      saturation: hsl.saturation,
      lightness: hsl.lightness,
      hatchOverdue: false,
      isPlannedGray: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _tasks
        .where(
          (t) => taskMatchesTagFilter(
            tagId: t.tagId,
            filterTagIds: widget.filterTagIds,
          ),
        )
        .toList();
    final selected = selectVisibleMonthTasks(
      month: _monthStart,
      tasks: filtered,
    );
    final weeks = buildMonthWeekLayouts(
      month: _monthStart,
      tasks: selected.visible,
      overflowByDay: selected.overflowByDay,
    );
    final byId = {for (final t in selected.visible) t.id: t};
    final headers = const ['一', '二', '三', '四', '五', '六', '日'];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              for (final h in headers)
                Expanded(
                  child: Center(
                    child: Text(h,
                        style: Theme.of(context).textTheme.labelLarge),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final weekCount = weeks.length;
              if (weekCount == 0) return const SizedBox.shrink();

              final equalHeight = constraints.maxHeight / weekCount;
              final minHeights = <double>[
                for (final week in weeks)
                  _dayHeaderHeight +
                      week.laneCount * (_barHeight + _barGap) +
                      4,
              ];
              final needsScroll =
                  minHeights.any((h) => h > equalHeight + 0.5);

              Widget weekRow(int index, double height) {
                return _WeekRow(
                  week: weeks[index],
                  month: _monthStart,
                  rowHeight: height,
                  barHeight: _barHeight,
                  barGap: _barGap,
                  dayHeaderHeight: _dayHeaderHeight,
                  minBarWidth: _minBarWidth,
                  paintFor: (id) => _paintFor(byId[id]!),
                  onOpenDay: widget.onOpenDay,
                );
              }

              if (needsScroll) {
                return ListView.builder(
                  itemCount: weekCount,
                  itemBuilder: (context, index) =>
                      weekRow(index, minHeights[index]),
                );
              }

              // Equal-height weeks fill the viewport (calendar grid).
              return Column(
                children: [
                  for (var i = 0; i < weekCount; i++)
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, c) => weekRow(i, c.maxHeight),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.week,
    required this.month,
    required this.rowHeight,
    required this.barHeight,
    required this.barGap,
    required this.dayHeaderHeight,
    required this.minBarWidth,
    required this.paintFor,
    required this.onOpenDay,
  });

  final MonthWeekLayout week;
  final DateTime month;
  final double rowHeight;
  final double barHeight;
  final double barGap;
  final double dayHeaderHeight;
  final double minBarWidth;
  final BarPaint Function(String taskId) paintFor;
  final void Function(DateTime day) onOpenDay;

  bool _inMonth(DateTime d) =>
      d.year == month.year && d.month == month.month;

  bool _isToday(DateTime d) {
    final n = DateTime.now();
    return n.year == d.year && n.month == d.month && n.day == d.day;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final cellW = w / 7;

          return Stack(
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final day in week.days)
                      Expanded(
                        child: _DayCell(
                          day: day,
                          inMonth: _inMonth(day),
                          isToday: _isToday(day),
                          overflow: _inMonth(day)
                              ? week.overflowByDay[day.day] ?? 0
                              : 0,
                          onTap: _inMonth(day)
                              ? () => onOpenDay(day)
                              : null,
                        ),
                      ),
                  ],
                ),
              ),
              for (final bar in week.bars)
                Builder(
                  builder: (context) {
                    var left = bar.startFrac / 7 * w;
                    var width = (bar.endFrac - bar.startFrac) / 7 * w;
                    // Same-day bars stay 2px inside the day-column grid lines;
                    // multi-day bars keep spanning through the dividers.
                    if (isSameCalendarDaySpan(bar.spanStart, bar.spanEnd)) {
                      const inset = 2.0;
                      final dayIndex =
                          bar.startFrac.floor().clamp(0, 6).toInt();
                      final minL = dayIndex * cellW + inset;
                      final maxR = (dayIndex + 1) * cellW - inset;
                      var right = (left + width).clamp(minL, maxR);
                      left = left.clamp(minL, maxR);
                      if (right < left) right = left;
                      width = right - left;
                    }
                    if (width < minBarWidth) width = minBarWidth;
                    if (left + width > w) left = (w - width).clamp(0.0, w);
                    final top = dayHeaderHeight +
                        bar.lane * (barHeight + barGap) +
                        2;
                    final paint = paintFor(bar.taskId);
                    final bg = colorOf(paint);
                    final fg = textColorOn(paint);
                    final label = Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          bar.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: fg,
                            height: 1.1,
                          ),
                        ),
                      ),
                    );
                    return Positioned(
                      left: left,
                      top: top,
                      width: width,
                      height: barHeight,
                      child: ExcludeSemantics(
                        child: BarDetailTooltip(
                          title: bar.title,
                          start: bar.spanStart,
                          end: bar.spanEnd,
                          focusDay: bar.openDay,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => onOpenDay(bar.openDay),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: bg,
                                ),
                                child: label,
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              // Keep day-tap targets above empty areas but below bars:
              // bars already have their own InkWell. Day cells underneath
              // receive taps in gaps.
              IgnorePointer(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    size: Size(w, h),
                    painter: _WeekGridPainter(cellW: cellW),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.overflow,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final int overflow;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isToday && inMonth
              ? primary.withValues(alpha: 0.06)
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  inMonth ? '${day.day}' : '',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                    color: !inMonth
                        ? Colors.transparent
                        : isToday
                            ? primary
                            : null,
                  ),
                ),
                if (overflow > 0) ...[
                  const Spacer(),
                  Text(
                    '+$overflow',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: primary,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekGridPainter extends CustomPainter {
  _WeekGridPainter({required this.cellW});

  final double cellW;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var i = 0; i <= 7; i++) {
      final x = i * cellW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    canvas.drawLine(Offset(0, size.height - 0.5),
        Offset(size.width, size.height - 0.5), paint);
  }

  @override
  bool shouldRepaint(covariant _WeekGridPainter oldDelegate) =>
      oldDelegate.cellW != cellW;
}
