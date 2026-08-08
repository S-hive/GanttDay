import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../day/day_gantt_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});

  final AppServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime _date = DateTime.now();

  void _shiftDay(int delta) {
    setState(() {
      _date = DateTime(_date.year, _date.month, _date.day + delta);
    });
  }

  Future<void> _seedSampleTasks() async {
    final day = DateTime(_date.year, _date.month, _date.day);
    const uuid = Uuid();
    final now = WallClock.now();
    await widget.services.tasks.upsert(Task(
      id: uuid.v4(),
      title: '剪辑客户宣传片',
      plannedStart: WallClock.minutes(day.add(const Duration(hours: 9))),
      plannedEnd: WallClock.minutes(day.add(const Duration(hours: 12))),
      autoHue: 210,
      createdAt: now,
    ));
    await widget.services.tasks.upsert(Task(
      id: uuid.v4(),
      title: '拍摄产品照片',
      plannedStart: WallClock.minutes(day.add(const Duration(hours: 11))),
      plannedEnd: WallClock.minutes(day.add(const Duration(hours: 14))),
      autoHue: 20,
      createdAt: now,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('GanttDay'),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: '前一天',
              onPressed: () => _shiftDay(-1),
            ),
            Text(dateLabel, style: const TextStyle(fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: '后一天',
              onPressed: () => _shiftDay(1),
            ),
            TextButton(
              onPressed: () => setState(() => _date = DateTime.now()),
              child: const Text('今天'),
            ),
          ],
        ),
        actions: [
          if (kDebugMode)
            IconButton(
              icon: const Icon(Icons.bug_report_outlined),
              tooltip: '插入示例任务（调试）',
              onPressed: _seedSampleTasks,
            ),
        ],
      ),
      body: DayGanttPage(services: widget.services, date: _date),
    );
  }
}
