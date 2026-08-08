import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../data/backup/backup_service.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/tag.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings _settings = const AppSettings();
  List<Tag> _tags = const [];
  String? _message;
  bool _busy = false;

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
    if (!mounted) return;
    setState(() {
      _settings = s;
      _tags = tags;
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

  Future<void> _addTag() async {
    final nameCtrl = TextEditingController();
    var hue = 200;
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
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor:
                        HSLColor.fromAHSL(1, hue.toDouble(), 0.7, 0.55)
                            .toColor(),
                  ),
                  Expanded(
                    child: Slider(
                      value: hue.toDouble(),
                      min: 0,
                      max: 359,
                      onChanged: (v) => setLocal(() => hue = v.round()),
                    ),
                  ),
                ],
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
      Tag(id: const Uuid().v4(), name: name, hue: hue),
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
              leading: CircleAvatar(
                backgroundColor:
                    HSLColor.fromAHSL(1, tag.hue.toDouble(), 0.7, 0.55)
                        .toColor(),
              ),
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
