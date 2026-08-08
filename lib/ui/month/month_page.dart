import 'dart:async';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';

/// Month grid: up to 3 titles per day + `+N`; tap a day to open day view.
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
  StreamSubscription<List<Task>>? _sub;
  List<Task> _tasks = const [];

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
    _sub?.cancel();
    final start = WallClock.minutes(_monthStart);
    final end = WallClock.minutes(_monthEndExclusive);
    _sub = widget.services.tasks
        .watchTasksOverlapping(start, end)
        .listen((tasks) {
      if (mounted) setState(() => _tasks = tasks);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Map<int, List<Task>> _tasksByDay() {
    final map = <int, List<Task>>{};
    for (final t in _tasks) {
      // Attribute a task to every day it overlaps within the month.
      var day = WallClock.dayStart(t.plannedStart);
      final end = t.plannedEnd;
      final monthStart = WallClock.minutes(_monthStart);
      final monthEnd = WallClock.minutes(_monthEndExclusive);
      if (day < monthStart) day = monthStart;
      while (day < end && day < monthEnd) {
        final dt = WallClock.dateTime(day);
        map.putIfAbsent(dt.day, () => []).add(t);
        day += WallClock.minutesPerDay;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final byDay = _tasksByDay();
    final firstWeekday = _monthStart.weekday; // 1=Mon … 7=Sun
    final daysInMonth =
        DateTime(widget.month.year, widget.month.month + 1, 0).day;
    final leading = firstWeekday - 1;
    final totalCells = ((leading + daysInMonth + 6) ~/ 7) * 7;

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
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 0.85,
            ),
            itemCount: totalCells,
            itemBuilder: (context, index) {
              final dayNum = index - leading + 1;
              if (dayNum < 1 || dayNum > daysInMonth) {
                return const SizedBox.shrink();
              }
              final day =
                  DateTime(widget.month.year, widget.month.month, dayNum);
              final list = byDay[dayNum] ?? const <Task>[];
              final shown = list.take(3).toList();
              final extra = list.length - shown.length;
              final isToday = () {
                final n = DateTime.now();
                return n.year == day.year &&
                    n.month == day.month &&
                    n.day == day.day;
              }();

              return InkWell(
                onTap: () => widget.onOpenDay(day),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(6),
                    color: isToday
                        ? Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.08)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$dayNum',
                        style: TextStyle(
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.w500,
                          color: isToday
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                      ),
                      for (final t in shown)
                        Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      if (extra > 0)
                        Text('+$extra',
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                            )),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
