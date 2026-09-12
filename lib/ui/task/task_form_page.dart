import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/models/color_swatch.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/inline_datetime.dart';
import '../../domain/time/wall_clock.dart';
import '../common/swatch_picker.dart';
import 'plan_datetime_accordion.dart';

/// Create / edit a task. Validates end > start before saving.
class TaskFormPage extends StatefulWidget {
  const TaskFormPage({
    super.key,
    required this.services,
    this.existing,
    this.initialStart,
    this.initialEnd,
  });

  final AppServices services;
  final Task? existing;

  /// Optional defaults when creating from a drag-create range.
  final WallMinutes? initialStart;
  final WallMinutes? initialEnd;

  @override
  State<TaskFormPage> createState() => _TaskFormPageState();
}

class _TaskFormPageState extends State<TaskFormPage> {
  late final TextEditingController _title;
  late final TextEditingController _notes;
  late final TextEditingController _planYear;
  late final TextEditingController _planMonth;
  late final TextEditingController _planDay;
  late final TextEditingController _planHour;
  late final TextEditingController _planMinute;
  late DateTime _start;
  late DateTime _end;
  String? _primaryTagId;
  String? _overrideSwatchId;
  List<Tag> _tags = const [];
  List<ColorSwatch> _swatches = const [];
  List<String> _tagIds = const [];
  String? _error;
  bool _saving = false;
  PlanEditorTarget _planEditor = PlanEditorTarget.none;
  String? _planEditorError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _title = TextEditingController(text: existing.title);
      _notes = TextEditingController(text: existing.notes ?? '');
      _start = WallClock.dateTime(existing.plannedStart);
      _end = WallClock.dateTime(existing.plannedEnd);
      _primaryTagId = existing.primaryTagId;
      _overrideSwatchId = existing.overrideSwatchId;
    } else {
      _title = TextEditingController();
      _notes = TextEditingController();
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day, 9);
      _start = widget.initialStart != null
          ? WallClock.dateTime(widget.initialStart!)
          : day;
      _end = widget.initialEnd != null
          ? WallClock.dateTime(widget.initialEnd!)
          : day.add(const Duration(hours: 1));
    }
    _planYear = TextEditingController();
    _planMonth = TextEditingController();
    _planDay = TextEditingController();
    _planHour = TextEditingController();
    _planMinute = TextEditingController();
    _loadTags();
  }

  Map<String, ColorSwatch> get _swatchesById =>
      {for (final s in _swatches) s.id: s};

  ColorSwatch? get _defaultSwatch {
    for (final s in _swatches) {
      if (s.isDefault) return s;
    }
    return _swatches.isEmpty ? null : _swatches.first;
  }

  Color _tagColor(String swatchId) {
    final swatch = _swatchesById[swatchId] ?? _defaultSwatch;
    if (swatch == null) return Colors.grey;
    return Color(swatch.argb);
  }

  Future<void> _loadTags() async {
    final tags = await widget.services.tasks.listTags();
    final swatches = await widget.services.tasks.listSwatches();
    List<String> assigned = const [];
    if (widget.existing != null) {
      assigned =
          await widget.services.tasks.tagIdsForTask(widget.existing!.id);
    }
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _swatches = swatches;
      _tagIds = assigned;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    _planYear.dispose();
    _planMonth.dispose();
    _planDay.dispose();
    _planHour.dispose();
    _planMinute.dispose();
    super.dispose();
  }

  void _fillPlanEditors(DateTime dt) {
    _planYear.text = '${dt.year}';
    _planMonth.text = dt.month.toString().padLeft(2, '0');
    _planDay.text = dt.day.toString().padLeft(2, '0');
    _planHour.text = dt.hour.toString().padLeft(2, '0');
    _planMinute.text = dt.minute.toString().padLeft(2, '0');
  }

  /// Commits open plan editor. Returns false if invalid (stays open).
  bool _commitPlanEditor() {
    if (_planEditor == PlanEditorTarget.none) return true;
    final parsed = InlineDateTimeParse.tryParse(
      year: _planYear.text,
      month: _planMonth.text,
      day: _planDay.text,
      hour: _planHour.text,
      minute: _planMinute.text,
    );
    if (parsed.value == null) {
      setState(() => _planEditorError = parsed.error ?? '日期无效');
      return false;
    }
    setState(() {
      if (_planEditor == PlanEditorTarget.start) {
        _start = parsed.value!;
      } else {
        _end = parsed.value!;
      }
      _planEditor = PlanEditorTarget.none;
      _planEditorError = null;
    });
    return true;
  }

  void _openPlanEditor(PlanEditorTarget target) {
    final dt = target == PlanEditorTarget.start ? _start : _end;
    _fillPlanEditors(dt);
    setState(() {
      _planEditor = target;
      _planEditorError = null;
    });
  }

  void _onTapPlanStart() {
    if (_planEditor == PlanEditorTarget.start) {
      _commitPlanEditor();
      return;
    }
    if (_planEditor == PlanEditorTarget.end) {
      if (!_commitPlanEditor()) return;
    }
    _openPlanEditor(PlanEditorTarget.start);
  }

  void _onTapPlanEnd() {
    if (_planEditor == PlanEditorTarget.end) {
      _commitPlanEditor();
      return;
    }
    if (_planEditor == PlanEditorTarget.start) {
      if (!_commitPlanEditor()) return;
    }
    _openPlanEditor(PlanEditorTarget.end);
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// Saves and closes the drawer on success. Returns false if validation /
  /// persistence failed (drawer stays open).
  Future<bool> _save() async {
    if (!_commitPlanEditor()) return false;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写任务名');
      return false;
    }
    final start = WallClock.minutes(_start);
    final end = WallClock.minutes(_end);
    if (end <= start) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return false;
    }
    if (end < start + GanttGeometry.minDurationMinutes) {
      setState(() => _error = '最短时长为 15 分钟');
      return false;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final Task task;
      if (_isEdit) {
        final e = widget.existing!;
        task = e.copyWith(
          title: title,
          plannedStart: start,
          plannedEnd: end,
          primaryTagId: _primaryTagId,
          overrideSwatchId: _overrideSwatchId,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          clearPrimaryTag: _primaryTagId == null,
          clearOverrideSwatch: _overrideSwatchId == null,
          clearNotes: _notes.text.trim().isEmpty,
        );
      } else {
        final defaultSwatch = await widget.services.tasks.defaultSwatch();
        task = Task(
          id: const Uuid().v4(),
          title: title,
          plannedStart: start,
          plannedEnd: end,
          primaryTagId: _primaryTagId,
          autoSwatchId: defaultSwatch.id,
          overrideSwatchId: _overrideSwatchId,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          createdAt: WallClock.now(),
        );
      }
      await widget.services.tasks.upsert(task);
      await widget.services.tasks.setTaskTags(task.id, _tagIds);
      if (!mounted) return false;
      Navigator.of(context).pop(task);
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
      return false;
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除任务'),
        content: const Text('确定删除这个任务？此操作不可撤销。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await widget.services.tasks.delete(widget.existing!.id);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Barrier / system back → save then close (Navigator.pop still works for
    // delete/complete which call pop directly).
    // Material required for TextFields when hosted outside Scaffold
    // (e.g. accidental MaterialPageRoute). Side drawer already provides one.
    return Material(
      color: theme.colorScheme.surface,
      child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _saving) return;
        await _save();
      },
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _isEdit ? '编辑任务' : '新建任务',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_isEdit)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '',
                  onPressed: _saving ? null : _delete,
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  labelText: '任务名',
                  border: OutlineInputBorder(),
                ),
                autofocus: !_isEdit,
              ),
              const SizedBox(height: 16),
              PlanDatetimeAccordion(
                startLabel: _fmt(_start),
                endLabel: _fmt(_end),
                target: _planEditor,
                year: _planYear,
                month: _planMonth,
                day: _planDay,
                hour: _planHour,
                minute: _planMinute,
                error: _planEditorError,
                onTapStart: _onTapPlanStart,
                onTapEnd: _onTapPlanEnd,
                onConfirm: _commitPlanEditor,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notes,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: '备注',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('主标签（决定颜色）',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('无'),
                    selected: _primaryTagId == null,
                    onSelected: (_) => setState(() => _primaryTagId = null),
                  ),
                  for (final tag in _tags)
                    ChoiceChip(
                      label: Text(tag.name),
                      selected: _primaryTagId == tag.id,
                      avatar: CircleAvatar(
                        backgroundColor: _tagColor(tag.swatchId),
                        radius: 8,
                      ),
                      onSelected: (_) => setState(() {
                        _primaryTagId = tag.id;
                        if (!_tagIds.contains(tag.id)) {
                          _tagIds = [..._tagIds, tag.id];
                        }
                      }),
                    ),
                ],
              ),
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('附加标签', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final tag in _tags)
                      FilterChip(
                        label: Text(tag.name),
                        selected: _tagIds.contains(tag.id),
                        onSelected: (sel) => setState(() {
                          if (sel) {
                            _tagIds = [..._tagIds, tag.id];
                          } else {
                            _tagIds =
                                _tagIds.where((id) => id != tag.id).toList();
                            if (_primaryTagId == tag.id) {
                              _primaryTagId = null;
                            }
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('手动覆盖颜色'),
                value: _overrideSwatchId != null,
                onChanged: (on) => setState(() {
                  _overrideSwatchId = on
                      ? (_overrideSwatchId ??
                          farthestSwatchId(
                            _swatches,
                            [
                              for (final t in _tags)
                                if (_swatchesById[t.swatchId]
                                    case final swatch?)
                                  swatch.hue,
                            ],
                          ))
                      : null;
                }),
              ),
              if (_overrideSwatchId != null)
                SwatchPicker(
                  swatches: _swatches,
                  swatchId: _overrideSwatchId!,
                  onChanged: (id) => setState(() => _overrideSwatchId = id),
                ),
            ],
          ),
        ),
        if (_error != null) ...[
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        ],
      ],
    ),
    ),
    );
  }
}
