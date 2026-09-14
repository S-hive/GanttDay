import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/default_color.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/inline_datetime.dart';
import '../../domain/time/wall_clock.dart';
import '../common/argb_color_field.dart';
import '../common/rect_swatch.dart';
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
  String? _tagId;
  int? _overrideArgb;
  List<Tag> _tags = const [];
  List<DefaultColor> _defaults = const [];
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
      _tagId = existing.tagId;
      _overrideArgb = existing.overrideArgb;
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

  Future<void> _loadTags() async {
    final tags = await widget.services.tasks.listTags();
    final defaults = await widget.services.tasks.listDefaultColors();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _defaults = defaults;
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
      final notes = _notes.text.trim().isEmpty ? null : _notes.text.trim();
      final Task task;
      if (_isEdit) {
        final e = widget.existing!;
        task = applyFormPaint(
          e.copyWith(
            title: title,
            plannedStart: start,
            plannedEnd: end,
            notes: notes,
            clearNotes: notes == null,
          ),
          tagId: _tagId,
          overrideArgb: _overrideArgb,
        );
      } else {
        task = applyFormPaint(
          Task(
            id: const Uuid().v4(),
            title: title,
            plannedStart: start,
            plannedEnd: end,
            notes: notes,
            createdAt: WallClock.now(),
          ),
          tagId: _tagId,
          overrideArgb: _overrideArgb,
        );
      }
      await widget.services.tasks.upsert(task);
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
              TagPickList(
                tags: _tags,
                selectedId: _tagId,
                onChanged: (id) => setState(() => _tagId = id),
              ),
              const SizedBox(height: 16),
              OverrideArgbRow(
                overrideArgb: _overrideArgb,
                tags: _tags,
                defaults: _defaults,
                onChanged: (argb) {
                  if (!mounted) return;
                  setState(() => _overrideArgb = argb);
                },
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

Task applyFormPaint(
  Task task, {
  required String? tagId,
  required int? overrideArgb,
}) {
  return task.copyWith(
    tagId: tagId,
    overrideArgb: overrideArgb,
    clearTag: tagId == null,
    clearOverrideArgb: overrideArgb == null,
  );
}

class TagPickList extends StatelessWidget {
  const TagPickList({
    super.key,
    required this.tags,
    required this.selectedId,
    required this.onChanged,
  });

  final List<Tag> tags;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('标签', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => onChanged(null),
              child: Text(
                '无',
                style: TextStyle(
                  fontWeight:
                      selectedId == null ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
            for (final tag in tags)
              GestureDetector(
                onTap: () => onChanged(tag.id),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RectSwatch(
                      argb: tag.argb,
                      selected: selectedId == tag.id,
                    ),
                    const SizedBox(width: 8),
                    Text(tag.name),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class OverrideArgbRow extends StatelessWidget {
  const OverrideArgbRow({
    super.key,
    required this.overrideArgb,
    required this.tags,
    required this.defaults,
    required this.onChanged,
    this.pickArgb,
  });

  final int? overrideArgb;
  final List<Tag> tags;
  final List<DefaultColor> defaults;
  final ValueChanged<int?> onChanged;
  final Future<int?> Function(
    BuildContext context, {
    required int initialArgb,
  })? pickArgb;

  List<int> _unionArgbs() {
    final seen = <int>{};
    final out = <int>[];
    for (final t in tags) {
      if (seen.add(t.argb)) out.add(t.argb);
    }
    for (final c in defaults) {
      if (seen.add(c.argb)) out.add(c.argb);
    }
    return out;
  }

  Future<void> _onEnabled(BuildContext context, bool on) async {
    if (!on) {
      onChanged(null);
      return;
    }
    final chips = _unionArgbs();
    if (chips.isEmpty) {
      final picker = pickArgb ?? showArgbColorPicker;
      final picked = await picker(context, initialArgb: kFallbackArgb);
      onChanged(picked);
      return;
    }
    onChanged(chips.first);
  }

  @override
  Widget build(BuildContext context) {
    final chips = _unionArgbs();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('手动覆盖颜色'),
          value: overrideArgb != null,
          onChanged: (on) => _onEnabled(context, on),
        ),
        if (overrideArgb != null)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final argb in chips)
                RectSwatch(
                  argb: argb,
                  selected: argb == overrideArgb,
                  onTap: () => onChanged(argb),
                ),
            ],
          ),
      ],
    );
  }
}
