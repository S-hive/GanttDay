import 'package:flutter/material.dart';

import '../../app.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../common/rect_swatch.dart';
import '../common/side_drawer.dart';
import '../day/day_gantt_page.dart';
import '../month/month_page.dart';
import '../settings/settings_page.dart';
import '../task/task_form_page.dart';
import '../week/week_gantt_page.dart';
import 'view_nav_bar.dart';

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

  /// Day actual-edit mode: hide AppBar; tip banner replaces it.
  bool _dayActualEditMode = false;

  @override
  void initState() {
    super.initState();
    _reloadTags();
  }

  Future<void> _reloadTags() async {
    final tags = await widget.services.tasks.listTags();
    if (mounted) {
      setState(() {
        _tags = tags;
      });
    }
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
    await showSideDrawer<void>(
      context: context,
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
    );
    await _reloadTags();
  }

  Future<void> _openSettings() async {
    await showSideDrawer<void>(
      context: context,
      builder: (_) => SettingsPage(services: widget.services),
    );
    await _reloadTags();
  }

  String get _titleLabel {
    if (_navIndex == 2) {
      return '${_date.year}-${_date.month.toString().padLeft(2, '0')}';
    }
    if (_navIndex == 1) {
      final day = DateTime(_date.year, _date.month, _date.day);
      final monday = day.subtract(Duration(days: day.weekday - 1));
      return '${monday.month}月 · 第${_weekOfMonth(monday)}周';
    }
    return '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
  }

  /// 1-based week index within [date]'s month (weeks start Monday).
  static int _weekOfMonth(DateTime date) {
    final first = DateTime(date.year, date.month, 1);
    return ((date.day + first.weekday - 2) ~/ 7) + 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _dayActualEditMode
          ? null
          : AppBar(
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
                if (_tags.isNotEmpty)
                  MenuAnchor(
                    builder: (context, controller, child) {
                      return IconButton(
                        tooltip: '标签筛选',
                        onPressed: () {
                          if (controller.isOpen) {
                            controller.close();
                          } else {
                            controller.open();
                          }
                        },
                        icon: Badge(
                          isLabelVisible: _filterTagIds.isNotEmpty,
                          smallSize: 8,
                          child: const Icon(Icons.filter_list),
                        ),
                      );
                    },
                    menuChildren: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 360),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _filterTagIds = {}),
                                child: Text(
                                  '全部',
                                  style: TextStyle(
                                    fontWeight: _filterTagIds.isEmpty
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              for (final tag in _tags)
                                GestureDetector(
                                  onTap: () => setState(() {
                                    final next = {..._filterTagIds};
                                    if (!next.remove(tag.id)) {
                                      next.add(tag.id);
                                    }
                                    _filterTagIds = next;
                                  }),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      RectSwatch(
                                        argb: tag.argb,
                                        selected:
                                            _filterTagIds.contains(tag.id),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(tag.name),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: '',
                  onPressed: _openSettings,
                ),
              ],
            ),
      body: _buildBody(),
      bottomNavigationBar: ViewNavBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() {
          _navIndex = i;
          _dayActualEditMode = false;
        }),
      ),
    );
  }

  Widget _buildBody() {
    switch (_navIndex) {
      case 1:
        // Dense week grid + Windows accessibility bridge: exclude the whole
        // page from semantics so AXTree doesn't spam / corrupt on tab switch.
        return ExcludeSemantics(
          child: WeekGanttPage(
            services: widget.services,
            anchorDate: _date,
            filterTagIds: _filterTagIds,
            onOpenDay: (day) => setState(() {
              _date = day;
              _navIndex = 0;
            }),
          ),
        );
      case 2:
        return ExcludeSemantics(
          child: MonthPage(
            services: widget.services,
            month: _date,
            filterTagIds: _filterTagIds,
            onOpenDay: (day) => setState(() {
              _date = day;
              _navIndex = 0;
            }),
          ),
        );
      default:
        return DayGanttPage(
          services: widget.services,
          date: _date,
          filterTagIds: _filterTagIds,
          onBarTap: (task) => _openForm(existing: task),
          onActualEditModeChanged: (active) {
            if (!mounted || _dayActualEditMode == active) return;
            setState(() => _dayActualEditMode = active);
          },
        );
    }
  }
}
