import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../domain/gantt/color_palette.dart';
import '../../domain/gantt/urgency_palette.dart';
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
  });

  final AppServices services;
  final DateTime month;
  final void Function(DateTime day) onOpenDay;

  @override
  State<MonthPage> createState() => _MonthPageState();
}

class _MonthPageState extends State<MonthPage> {
  static const double _barHeight = 15;
  static const double _barGap = 2;
  static const double _dayHeaderHeight = 22;
  static const double _minBarWidth = 4;

  StreamSubscription<List<Task>>? _tasksSub;
  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};

  DateTime get _monthStart =>
      DateTime(widget.month.year, widget.month.month, 1);

  DateTime get _monthEndExclusive =>
      DateTime(widget.month.year, widget.month.month + 1, 1);

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(MonthPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.month != widget.month) _subscribe();
  }

  void _subscribe() {
    _tasksSub?.cancel();
    final start = WallClock.minutes(_monthStart);
    final end = WallClock.minutes(_monthEndExclusive);
    _tasksSub = widget.services.tasks
        .watchTasksOverlapping(start, end)
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
    super.dispose();
  }

  /// Month bars keep the task's base palette color. Done / unfinished look the
  /// same; overdue unfinished tasks are gray.
  BarPaint _paintFor(Task task) {
    final hue =
        task.overrideHue ?? _tags[task.primaryTagId]?.hue ?? task.autoHue;
    final overdue = !task.isDone && task.plannedEnd < WallClock.now();
    if (overdue) {
      return BarPaint(
        hue: hue,
        saturation: 0.12,
        lightness: 0.55,
        hatchOverdue: false,
        isPlannedGray: true,
      );
    }
    final swatch = swatchForHue(hue);
    return BarPaint(
      hue: hue,
      saturation: swatch?.saturation ?? UrgencyPalette.minSaturation,
      lightness: swatch?.lightness ?? UrgencyPalette.calmLightness,
      hatchOverdue: false,
      isPlannedGray: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = selectVisibleMonthTasks(
      month: _monthStart,
      tasks: _tasks,
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
          child: ListView.builder(
            itemCount: weeks.length,
            itemBuilder: (context, index) {
              final week = weeks[index];
              return _WeekRow(
                week: week,
                month: _monthStart,
                barHeight: _barHeight,
                barGap: _barGap,
                dayHeaderHeight: _dayHeaderHeight,
                minBarWidth: _minBarWidth,
                paintFor: (id) => _paintFor(byId[id]!),
                onOpenDay: widget.onOpenDay,
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
    required this.barHeight,
    required this.barGap,
    required this.dayHeaderHeight,
    required this.minBarWidth,
    required this.paintFor,
    required this.onOpenDay,
  });

  final MonthWeekLayout week;
  final DateTime month;
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
    final lanes = week.laneCount;
    final barsHeight = lanes * (barHeight + barGap) + 4;
    final rowHeight = dayHeaderHeight + barsHeight;

    return SizedBox(
      height: rowHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final cellW = w / 7;

          return Stack(
            children: [
              Row(
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
                              borderRadius: BorderRadius.circular(5),
                              onTap: () => onOpenDay(bar.openDay),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: bg,
                                  borderRadius: BorderRadius.circular(5),
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
                    size: Size(w, rowHeight),
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
