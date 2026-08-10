import 'dart:math' as math;

import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../data/backup/backup_service.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/color_swatch.dart';
import '../../domain/models/tag.dart';
import '../common/argb_color_field.dart';
import '../common/swatch_picker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings _settings = const AppSettings();
  List<Tag> _tags = const [];
  List<ColorSwatch> _swatches = const [];
  String? _message;
  bool _busy = false;

  Map<String, ColorSwatch> get _swatchesById =>
      {for (final s in _swatches) s.id: s};

  @override
  void initState() {
    super.initState();
    _reload();
    widget.services.settings.watch().listen((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  Future<void> _reload() async {
    final s = await widget.services.settings.read();
    final tags = await widget.services.tasks.listTags();
    final swatches = await widget.services.tasks.listSwatches();
    if (!mounted) return;
    setState(() {
      _settings = s;
      _tags = tags;
      _swatches = swatches;
    });
  }

  Future<void> _write(AppSettings next) async {
    try {
      await widget.services.settings.write(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '保存设置失败：$e');
    }
  }

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

  Future<void> _setDefaultSwatch(ColorSwatch swatch) async {
    if (swatch.isDefault) return;
    try {
      await widget.services.tasks.setDefaultSwatch(swatch.id);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '设置默认色卡失败：$e');
    }
  }

  Future<void> _showSwatchDialog({ColorSwatch? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final defaultArgb = _defaultSwatch?.argb ?? 0xFF457BD9;
    var argb = existing?.argb ?? defaultArgb;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing == null ? '新建色卡' : '编辑色卡'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              ArgbColorField(
                argb: argb,
                onChanged: (v) => setLocal(() => argb = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final maxSort = _swatches.isEmpty
        ? -1
        : _swatches.map((s) => s.sortOrder).reduce(math.max);
    final swatch = colorSwatchFromArgb(
      id: existing?.id ?? const Uuid().v4(),
      name: name,
      argb: argb,
      sortOrder: existing?.sortOrder ?? maxSort + 1,
      isDefault: existing?.isDefault ?? false,
      slate: existing?.slate ?? false,
    );
    try {
      await widget.services.tasks.upsertSwatch(swatch);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '保存色卡失败：$e');
    }
  }

  Future<void> _deleteSwatch(ColorSwatch victim) async {
    if (_swatches.length <= 1) return;

    final others = _swatches.where((s) => s.id != victim.id).toList();
    final currentDefault = _defaultSwatch ?? others.first;
    var rebindToId = victim.isDefault ? others.first.id : currentDefault.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('删除色卡「${victim.name}」？'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('引用该色卡的任务与标签将改绑到：'),
              const SizedBox(height: 12),
              InputDecorator(
                decoration: const InputDecoration(labelText: '改绑目标'),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: rebindToId,
                    items: [
                      for (final s in others)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            s.id == currentDefault.id && !victim.isDefault
                                ? '${s.name}（当前默认）'
                                : s.name,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setLocal(() => rebindToId = v);
                    },
                  ),
                ),
              ),
              if (victim.isDefault) ...[
                const SizedBox(height: 8),
                const Text('删除默认色卡后，改绑目标将成为新的默认色卡。'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    try {
      if (victim.isDefault) {
        await widget.services.tasks.setDefaultSwatch(rebindToId);
      }
      await widget.services.tasks.deleteSwatch(victim.id, rebindToId: rebindToId);
      await _reload();
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '删除色卡失败：$e');
    }
  }

  Future<void> _addTag() async {
    final nameCtrl = TextEditingController();
    var swatchId = farthestSwatchId(
      _swatches,
      [
        for (final t in _tags)
          if (_swatchesById[t.swatchId] case final swatch?) swatch.hue,
      ],
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('新建标签'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '名称'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              SwatchPicker(
                swatches: _swatches,
                swatchId: swatchId,
                onChanged: (id) => setLocal(() => swatchId = id),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('创建')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await widget.services.tasks.upsertTag(
      Tag(id: const Uuid().v4(), name: name, swatchId: swatchId),
    );
    await _reload();
  }

  Future<void> _deleteTag(Tag tag) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除标签「${tag.name}」？'),
        content: const Text('关联会断开，使用该主标签的任务将回退到自动色相。'),
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
    if (ok != true) return;
    await widget.services.tasks.deleteTag(tag.id);
    await _reload();
  }

  Future<void> _export() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await widget.services.files.pickSavePath(
        suggestedName: 'gantday-backup.json',
        extensions: ['json'],
      );
      if (path == null) return;
      final svc = BackupService(
        widget.services.db,
        widget.services.tasks,
        widget.services.settings,
      );
      final json = await svc.exportJson();
      await widget.services.files.writeText(path, json);
      if (!mounted) return;
      setState(() => _message = '已导出到 $path');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '导出失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final path = await widget.services.files.pickOpenPath(extensions: ['json']);
      if (path == null) return;
      final text = await widget.services.files.readText(path);
      final svc = BackupService(
        widget.services.db,
        widget.services.tasks,
        widget.services.settings,
      );
      final result = await svc.importJson(text);
      if (!mounted) return;
      setState(() {
        _message =
            '导入完成：新增 ${result.importedTasks} 个任务、${result.importedTags} 个标签；'
            '跳过 ${result.skippedDuplicates} 个重复任务';
      });
      await _reload();
    } on BackupValidationException catch (e) {
      if (!mounted) return;
      setState(() => _message = '导入被拒绝：\n${e.problems.join('\n')}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _message = '导入失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sortedSwatches = [..._swatches]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('可视时段', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '开始小时'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _settings.visibleStartHour,
                      items: [
                        for (var h = 0; h < 24; h++)
                          DropdownMenuItem(value: h, child: Text('$h:00')),
                      ],
                      onChanged: (v) {
                        if (v == null || v >= _settings.visibleEndHour) return;
                        _write(_settings.copyWith(visibleStartHour: v));
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: '结束小时'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _settings.visibleEndHour,
                      items: [
                        for (var h = 1; h <= 24; h++)
                          DropdownMenuItem(
                              value: h,
                              child: Text(h == 24 ? '24:00' : '$h:00')),
                      ],
                      onChanged: (v) {
                        if (v == null || v <= _settings.visibleStartHour) {
                          return;
                        }
                        _write(_settings.copyWith(visibleEndHour: v));
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('紧迫窗口（天）', style: Theme.of(context).textTheme.titleMedium),
          Slider(
            value: _settings.urgencyWindowDays.toDouble().clamp(1, 30),
            min: 1,
            max: 30,
            divisions: 29,
            label: '${_settings.urgencyWindowDays}',
            onChanged: (v) =>
                _write(_settings.copyWith(urgencyWindowDays: v.round())),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('色卡', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _swatches.isEmpty ? null : () => _showSwatchDialog(),
                icon: const Icon(Icons.add),
                label: const Text('新建'),
              ),
            ],
          ),
          for (final s in sortedSwatches)
            ListTile(
              leading: CircleAvatar(backgroundColor: Color(s.argb)),
              title: Text(s.name),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(s.isDefault ? Icons.star : Icons.star_border),
                    tooltip: '设为默认',
                    onPressed:
                        s.isDefault ? null : () => _setDefaultSwatch(s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: '编辑',
                    onPressed: () => _showSwatchDialog(existing: s),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除',
                    onPressed: _swatches.length <= 1
                        ? null
                        : () => _deleteSwatch(s),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('标签', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton.icon(
                onPressed: _addTag,
                icon: const Icon(Icons.add),
                label: const Text('新建'),
              ),
            ],
          ),
          for (final tag in _tags)
            ListTile(
              leading: CircleAvatar(backgroundColor: _tagColor(tag.swatchId)),
              title: Text(tag.name),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteTag(tag),
              ),
            ),
          const SizedBox(height: 24),
          Text('备份', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.upload_file),
                label: const Text('导出'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.download),
                label: const Text('导入'),
              ),
            ],
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!),
          ],
        ],
      ),
    );
  }
}
