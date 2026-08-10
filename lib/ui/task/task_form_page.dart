import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/gantt/gantt_geometry.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../common/swatch_picker.dart';
import '../complete/complete_dialog.dart';

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
  late DateTime _start;
  late DateTime _end;
  String? _primaryTagId;
  String? _overrideSwatchId;
  List<Tag> _tags = const [];
  List<String> _tagIds = const [];
  String? _error;
  bool _saving = false;

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
    _loadTags();
  }

  Future<void> _loadTags() async {
    final tags = await widget.services.tasks.listTags();
    List<String> assigned = const [];
    if (widget.existing != null) {
      assigned =
          await widget.services.tasks.tagIdsForTask(widget.existing!.id);
    }
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _tagIds = assigned;
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) return;
    // Snap to nearest 15 minutes for consistency with the Gantt.
    final minutes = time.hour * 60 + time.minute;
    final snapped = ((minutes + 7) ~/ 15) * 15;
    final dt = DateTime(
      date.year,
      date.month,
      date.day,
      snapped ~/ 60,
      snapped % 60,
    );
    setState(() {
      if (isStart) {
        _start = dt;
      } else {
        _end = dt;
      }
      _error = null;
    });
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请填写任务名');
      return;
    }
    final start = WallClock.minutes(_start);
    final end = WallClock.minutes(_end);
    if (end <= start) {
      setState(() => _error = '结束时间必须晚于开始时间');
      return;
    }
    if (end < start + GanttGeometry.minDurationMinutes) {
      setState(() => _error = '最短时长为 15 分钟');
      return;
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
        task = Task(
          id: const Uuid().v4(),
          title: title,
          plannedStart: start,
          plannedEnd: end,
          primaryTagId: _primaryTagId,
          autoSwatchId: kDefaultSwatchId,
          overrideSwatchId: _overrideSwatchId,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
          createdAt: WallClock.now(),
        );
      }
      await widget.services.tasks.upsert(task);
      await widget.services.tasks.setTaskTags(task.id, _tagIds);
      if (!mounted) return;
      Navigator.of(context).pop(task);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存失败：$e';
      });
    }
  }

  Future<void> _markComplete() async {
    final existing = widget.existing!;
    final result = await showCompleteDialog(context, task: existing);
    if (result == null || !mounted) return;
    try {
      await widget.services.tasks.complete(
        existing.id,
        actualStart: result.start,
        actualEnd: result.end,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '标记完成失败：$e');
    }
  }

  Future<void> _uncomplete() async {
    try {
      await widget.services.tasks.uncomplete(widget.existing!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '撤销完成失败：$e');
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? '编辑任务' : '新建任务'),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '',
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('计划开始'),
            subtitle: Text(_fmt(_start)),
            trailing: const Icon(Icons.schedule),
            onTap: () => _pickDateTime(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('计划结束'),
            subtitle: Text(_fmt(_end)),
            trailing: const Icon(Icons.schedule),
            onTap: () => _pickDateTime(isStart: false),
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
          Text('主标签（决定颜色）', style: Theme.of(context).textTheme.titleSmall),
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
                    backgroundColor: HSLColor.fromAHSL(
                            1,
                            hueForSwatchId(tag.swatchId).toDouble(),
                            0.7,
                            0.55)
                        .toColor(),
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
            Text('附加标签', style: Theme.of(context).textTheme.titleSmall),
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
                        if (_primaryTagId == tag.id) _primaryTagId = null;
                      }
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('手动覆盖色相'),
            value: _overrideSwatchId != null,
            onChanged: (on) => setState(() {
              _overrideSwatchId = on
                  ? (_overrideSwatchId ??
                      farthestSwatchId(
                        kFactoryColorSwatches,
                        [
                          for (final t in _tags)
                            hueForSwatchId(t.swatchId),
                        ],
                      ))
                  : null;
            }),
          ),
          if (_overrideSwatchId != null)
            SwatchPicker(
              swatches: kFactoryColorSwatches,
              swatchId: _overrideSwatchId!,
              onChanged: (id) => setState(() => _overrideSwatchId = id),
            ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中…' : '保存'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 12),
            if (!widget.existing!.isDone)
              OutlinedButton.icon(
                onPressed: _saving ? null : _markComplete,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('标记完成'),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _saving ? null : _markComplete,
                icon: const Icon(Icons.edit_calendar_outlined),
                label: const Text('修改实际时间'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _saving ? null : _uncomplete,
                icon: const Icon(Icons.undo),
                label: const Text('撤销完成'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
