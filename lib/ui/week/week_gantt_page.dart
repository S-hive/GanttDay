import 'dart:async';

import 'package:flutter/material.dart' hide ColorSwatch;

import '../../app.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/gantt/urgency_palette.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/color_swatch.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../common/bar_detail_tooltip.dart';
import '../day/day_gantt_painter.dart';
import '../task/task_form_page.dart';
import 'week_column_layout.dart';

/// Week calendar: columns = Mon–Sun, rows = time of day.
class WeekGanttPage extends StatefulWidget {
  const WeekGanttPage({
    super.key,
    required this.services,
    required this.anchorDate,
    this.filterTagIds = const {},
    this.onOpenDay,
  });

  final AppServices services;
  final DateTime anchorDate;
  final Set<String> filterTagIds;
  final void Function(DateTime day)? onOpenDay;

  @override
  State<WeekGanttPage> createState() => _WeekGanttPageState();
}

class _WeekGanttPageState extends State<WeekGanttPage> {
  static const double _hourHeight = 48;
  static const double _gutterWidth = 52;
  static const double _dayHeaderHeight = 36;
  static const Color _dayBoundaryColor = Color(0xFFC62828);
  static const double _dayBoundaryGap = 3;
  static const double _dayBoundaryWidth = 1;
  static const double _dayBoundaryStride =
      _dayBoundaryGap * 2 + _dayBoundaryWidth;

  /// Thin red rule with 3px air on each side between day columns.
  /// Parent [Row] should use [CrossAxisAlignment.stretch] so the rule fills height.
  Widget _dayBoundary() {
    return const IgnorePointer(
      child: SizedBox(
        width: _dayBoundaryStride,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _dayBoundaryGap),
          child: ColoredBox(color: _dayBoundaryColor),
        ),
      ),
    );
  }

  StreamSubscription<List<Task>>? _tasksSub;
  StreamSubscription<List<ColorSwatch>>? _swatchesSub;
  StreamSubscription<AppSettings>? _settingsSub;
  final ScrollController _vScroll = ScrollController();
  bool _didInitialScroll = false;

  List<Task> _tasks = const [];
  Map<String, Tag> _tags = const {};
  Map<String, ColorSwatch> _swatchesById = const {};
  AppSettings _settings = const AppSettings();

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
    _swatchesSub = widget.services.tasks.watchSwatches().listen((swatches) {
      if (!mounted) return;
      setState(() {
        _swatchesById = {for (final s in swatches) s.id: s};
      });
    });
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
    _swatchesSub?.cancel();
    _settingsSub?.cancel();
    _vScroll.dispose();
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

  ColorSwatch get _defaultSwatch =>
      _swatchesById[kDefaultSwatchId] ??
      kFactoryColorSwatches.firstWhere((s) => s.isDefault);

  /// Same as month: base swatch color; overdue unfinished → gray.
  BarPaint _paintFor(Task task) {
    final id = resolveTaskSwatchId(task, _tags);
    final base = _swatchesById[id] ?? _defaultSwatch;
    final overdue = !task.isDone && task.plannedEnd < WallClock.now();
    if (overdue) {
      return BarPaint(
        hue: base.hue,
        saturation: 0.12,
        lightness: 0.55,
        hatchOverdue: false,
        isPlannedGray: true,
      );
    }
    return BarPaint(
      hue: base.hue,
      saturation: base.saturation,
      lightness: base.lightness,
      hatchOverdue: false,
      isPlannedGray: false,
    );
  }

  void _scrollToVisibleHours() {
    if (_didInitialScroll || !_vScroll.hasClients) return;
    _didInitialScroll = true;
    final target = _settings.visibleStartHour * _hourHeight;
    final max = _vScroll.position.maxScrollExtent;
    _vScroll.jumpTo(target.clamp(0.0, max));
  }

  Future<void> _openTask(Task task) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TaskFormPage(
        services: widget.services,
        existing: task,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final slots = layoutWeekSlots(weekMonday: _weekStart, tasks: _filtered);
    final byId = {for (final t in _filtered) t.id: t};
    final headers = const ['一', '二', '三', '四', '五', '六', '日'];
    final bodyHeight = 24 * _hourHeight;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayIndex = today.difference(_weekStart).inDays;
    final nowFrac = (now.hour * 60 + now.minute) / WallClock.minutesPerDay;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToVisibleHours());

    return Column(
      children: [
        SizedBox(
          height: _dayHeaderHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: _gutterWidth),
              for (var d = 0; d < 7; d++) ...[
                if (d > 0) _dayBoundary(),
                Expanded(
                  child: _DayHeader(
                    weekday: headers[d],
                    day: _weekStart.add(Duration(days: d)),
                    isToday: d == todayIndex,
                    onTap: widget.onOpenDay == null
                        ? null
                        : () => widget.onOpenDay!(
                              _weekStart.add(Duration(days: d)),
                            ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            controller: _vScroll,
            child: SizedBox(
              height: bodyHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: _gutterWidth,
                    child: Column(
                      children: [
                        for (var h = 0; h < 24; h++)
                          SizedBox(
                            height: _hourHeight,
                            child: Align(
                              alignment: Alignment.topRight,
                              child: Padding(
                                padding:
                                    const EdgeInsets.only(right: 6, top: 2),
                                child: Text(
                                  '$h:00',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var d = 0; d < 7; d++) ...[
                              if (d > 0) _dayBoundary(),
                              Expanded(
                                child: _DayColumn(
                                  isToday: d == todayIndex,
                                  hourHeight: _hourHeight,
                                  slots: slots
                                      .where((s) => s.dayIndex == d)
                                      .toList(),
                                  paintFor: (id) => _paintFor(byId[id]!),
                                  onTap: (id) => _openTask(byId[id]!),
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (todayIndex >= 0 && todayIndex < 7)
                          Positioned(
                            top: nowFrac * bodyHeight - 1,
                            left: 0,
                            right: 0,
                            height: 2,
                            child: IgnorePointer(
                              child: Row(
                                children: [
                                  for (var d = 0; d < 7; d++) ...[
                                    if (d > 0)
                                      const SizedBox(width: _dayBoundaryStride),
                                    Expanded(
                                      child: d == todayIndex
                                          ? ColoredBox(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error,
                                            )
                                          : const SizedBox.expand(),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.weekday,
    required this.day,
    required this.isToday,
    this.onTap,
  });

  final String weekday;
  final DateTime day;
  final bool isToday;
  final VoidCallback? onTap;

  /// Compact same-line label: `一 3/9`.
  String get _label => '$weekday ${day.month}/${day.day}';

  @override
  Widget build(BuildContext context) {
    const todayRed = Color(0xFFC62828);
    final label = Text(
      _label,
      maxLines: 1,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            fontWeight: isToday ? FontWeight.w700 : null,
          ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: isToday
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      border: Border.all(color: todayRed, width: 1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: label,
                  )
                : label,
          ),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.isToday,
    required this.hourHeight,
    required this.slots,
    required this.paintFor,
    required this.onTap,
  });

  final bool isToday;
  final double hourHeight;
  final List<WeekSlot> slots;
  final BarPaint Function(String taskId) paintFor;
  final void Function(String taskId) onTap;

  static Positioned _slotPositioned({
    required WeekSlot slot,
    required double dayHeight,
    required double columnWidth,
    required BarPaint paint,
    required VoidCallback onTap,
  }) {
    final top = slot.topFrac * dayHeight;
    var height = slot.heightFrac * dayHeight;
    if (height < 18) height = 18;
    final widthFrac = 1 / slot.columnCount;
    final left = slot.columnIndex * widthFrac * columnWidth + 1.5;
    // Keep a positive width even when many overlapping columns shrink the slot.
    final width = (widthFrac * columnWidth - 3).clamp(4.0, columnWidth);
    final bg = colorOf(paint);
    final fg = textColorOn(paint);
    final focusDay = WallClock.dateTime(WallClock.dayStart(slot.segStart));
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Align(
        alignment: Alignment.topLeft,
        child: Text(
          slot.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: fg,
            height: 1.15,
          ),
        ),
      ),
    );
    return Positioned(
      left: left,
      width: width,
      top: top,
      height: height,
      // Dense Tooltip+Stack trees trip Windows semantics assertions; bars
      // already expose their title via Text.
      child: ExcludeSemantics(
        child: BarDetailTooltip(
          title: slot.title,
          start: slot.spanStart,
          end: slot.spanEnd,
          focusDay: focusDay,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
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
  }

  @override
  Widget build(BuildContext context) {
    final dayH = 24 * hourHeight;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isToday
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.04)
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          // Keep the hour grid as a sibling, not a CustomPaint parent of the
          // interactive Stack — nesting caused semantics.parentDataDirty spam.
          return Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: CustomPaint(
                    painter: _HourGridPainter(hourHeight: hourHeight),
                  ),
                ),
              ),
              for (final slot in slots)
                _slotPositioned(
                  slot: slot,
                  dayHeight: dayH,
                  columnWidth: w,
                  paint: paintFor(slot.taskId),
                  onTap: () => onTap(slot.taskId),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HourGridPainter extends CustomPainter {
  _HourGridPainter({required this.hourHeight});

  final double hourHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var h = 0; h <= 24; h++) {
      final y = h * hourHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _HourGridPainter oldDelegate) =>
      oldDelegate.hourHeight != hourHeight;
}
