import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../day/day_gantt_page.dart';
import '../month/month_page.dart';
import '../settings/settings_page.dart';
import '../task/task_form_page.dart';
import '../week/week_gantt_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.services});

  final AppServices services;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  DateTime _date = DateTime.now();
  int _navIndex = 0; // 0 day, 1 week, 2 month
  Set<String> _filterTagIds = {};
  List<Tag> _tags = const [];

  @override
  void initState() {
    super.initState();
    _reloadTags();
  }

  Future<void> _reloadTags() async {
    final tags = await widget.services.tasks.listTags();
    if (mounted) setState(() => _tags = tags);
  }

  void _shift(int delta) {
    setState(() {
      if (_navIndex == 2) {
        _date = DateTime(_date.year, _date.month + delta, 1);
      } else if (_navIndex == 1) {
        _date = DateTime(_date.year, _date.month, _date.day + 7 * delta);
      } else {
        _date = DateTime(_date.year, _date.month, _date.day + delta);
      }
    });
  }

  Future<void> _openForm({Task? existing}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskFormPage(
          services: widget.services,
          existing: existing,
          initialStart: existing == null
              ? WallClock.minutes(
                  DateTime(_date.year, _date.month, _date.day, 9))
              : null,
          initialEnd: existing == null
              ? WallClock.minutes(
                  DateTime(_date.year, _date.month, _date.day, 10))
              : null,
        ),
      ),
    );
    await _reloadTags();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsPage(services: widget.services),
      ),
    );
    await _reloadTags();
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

  String get _titleLabel {
    if (_navIndex == 2) {
      return '${_date.year}-${_date.month.toString().padLeft(2, '0')}';
    }
    return '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('GanttDay'),
            const SizedBox(width: 24),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shift(-1),
            ),
            Text(_titleLabel, style: const TextStyle(fontSize: 16)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(1),
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
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: _openSettings,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_tags.isNotEmpty && _navIndex != 2)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: _filterTagIds.isEmpty,
                      onSelected: (_) => setState(() => _filterTagIds = {}),
                    ),
                    for (final tag in _tags)
                      FilterChip(
                        label: Text(tag.name),
                        selected: _filterTagIds.contains(tag.id),
                        avatar: CircleAvatar(
                          backgroundColor: HSLColor.fromAHSL(
                                  1, tag.hue.toDouble(), 0.7, 0.55)
                              .toColor(),
                          radius: 8,
                        ),
                        onSelected: (sel) => setState(() {
                          final next = {..._filterTagIds};
                          if (sel) {
                            next.add(tag.id);
                          } else {
                            next.remove(tag.id);
                          }
                          _filterTagIds = next;
                        }),
                      ),
                  ],
                ),
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton: _navIndex == 2
          ? null
          : FloatingActionButton(
              onPressed: () => _openForm(),
              tooltip: '新建任务',
              child: const Icon(Icons.add),
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.view_day_outlined), label: '日'),
          NavigationDestination(icon: Icon(Icons.view_week_outlined), label: '周'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined), label: '月'),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_navIndex) {
      case 1:
        return WeekGanttPage(
          services: widget.services,
          anchorDate: _date,
          filterTagIds: _filterTagIds,
        );
      case 2:
        return MonthPage(
          services: widget.services,
          month: _date,
          onOpenDay: (day) => setState(() {
            _date = day;
            _navIndex = 0;
          }),
        );
      default:
        return DayGanttPage(
          services: widget.services,
          date: _date,
          filterTagIds: _filterTagIds,
          onBarTap: (task) => _openForm(existing: task),
        );
    }
  }
}
