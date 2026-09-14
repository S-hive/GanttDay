import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../app.dart';
import '../../data/backup/backup_service.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/models/default_color.dart';
import '../../domain/models/tag.dart';
import '../../platform/task_repository.dart';
import '../common/argb_color_field.dart';
import '../common/rect_swatch.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.services});

  final AppServices services;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  List<Tag> _tags = const [];
  List<DefaultColor> _defaults = const [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final tags = await widget.services.tasks.listTags();
    final defaults = await widget.services.tasks.listDefaultColors();
    if (!mounted) return;
    setState(() {
      _tags = tags;
      _defaults = defaults;
    });
  }

  void _setMessage(String text) {
    setState(() => _message = text);
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
      final path =
          await widget.services.files.pickOpenPath(extensions: ['json']);
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            '设置',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TagSettingsList(
                tags: _tags,
                onRecolor: (tag, argb) async {
                  try {
                    await widget.services.tasks.upsertTag(
                      Tag(
                        id: tag.id,
                        name: tag.name,
                        argb: argb,
                        sortOrder: tag.sortOrder,
                      ),
                    );
                    await _reload();
                  } on TagOperationException catch (e) {
                    _setMessage(e.message);
                  }
                },
                onRename: (tag, name) async {
                  try {
                    await widget.services.tasks.upsertTag(
                      Tag(
                        id: tag.id,
                        name: name,
                        argb: tag.argb,
                        sortOrder: tag.sortOrder,
                      ),
                    );
                    await _reload();
                  } on TagOperationException catch (e) {
                    _setMessage(e.message);
                  }
                },
                onDelete: (tag) async {
                  await widget.services.tasks.deleteTag(tag.id);
                  await _reload();
                },
                onCreate: (name, argb) async {
                  try {
                    await widget.services.tasks.upsertTag(
                      Tag(
                        id: const Uuid().v4(),
                        name: name,
                        argb: argb,
                        sortOrder: _tags.length,
                      ),
                    );
                    await _reload();
                  } on TagOperationException catch (e) {
                    _setMessage(e.message);
                  }
                },
              ),
              const SizedBox(height: 24),
              DefaultColorSettingsList(
                colors: _defaults,
                onRecolor: (color, argb) async {
                  await widget.services.tasks.upsertDefaultColor(
                    DefaultColor(
                      id: color.id,
                      argb: argb,
                      sortOrder: color.sortOrder,
                      isCurrent: color.isCurrent,
                    ),
                  );
                  await _reload();
                },
                onDelete: (color) async {
                  await widget.services.tasks.deleteDefaultColor(color.id);
                  await _reload();
                },
                onCreate: (argb) async {
                  await widget.services.tasks.upsertDefaultColor(
                    DefaultColor(
                      id: const Uuid().v4(),
                      argb: argb,
                      sortOrder: _defaults.length,
                      isCurrent: true,
                    ),
                  );
                  await _reload();
                },
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
        ),
      ],
    );
  }
}

class TagSettingsList extends StatefulWidget {
  const TagSettingsList({
    super.key,
    required this.tags,
    required this.onRecolor,
    required this.onRename,
    required this.onDelete,
    required this.onCreate,
  });

  final List<Tag> tags;
  final Future<void> Function(Tag tag, int argb) onRecolor;
  final Future<void> Function(Tag tag, String name) onRename;
  final Future<void> Function(Tag tag) onDelete;
  final Future<void> Function(String name, int argb) onCreate;

  @override
  State<TagSettingsList> createState() => _TagSettingsListState();
}

class _TagSettingsListState extends State<TagSettingsList> {
  String? _editingId;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickColor(Tag tag) async {
    final argb = await showArgbColorPicker(context, initialArgb: tag.argb);
    if (argb == null) return;
    await widget.onRecolor(tag, argb);
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    var argb = kFallbackArgb;
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
              RectSwatch(
                argb: argb,
                onTap: () async {
                  final picked = await showArgbColorPicker(
                    ctx,
                    initialArgb: argb,
                  );
                  if (picked != null) setLocal(() => argb = picked);
                },
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
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok != true) return;
    if (name.isEmpty) return;
    await widget.onCreate(name, argb);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('标签', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
          ],
        ),
        for (final tag in widget.tags)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                RectSwatch(
                  argb: tag.argb,
                  onTap: () => _pickColor(tag),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _editingId == tag.id
                      ? TextField(
                          controller: _nameCtrl,
                          autofocus: true,
                          onSubmitted: (raw) async {
                            final name = raw.trim();
                            setState(() => _editingId = null);
                            if (name.isEmpty) return;
                            await widget.onRename(tag, name);
                          },
                        )
                      : GestureDetector(
                          onTap: () {
                            setState(() {
                              _editingId = tag.id;
                              _nameCtrl.text = tag.name;
                            });
                          },
                          child: Text(tag.name),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => widget.onDelete(tag),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class DefaultColorSettingsList extends StatelessWidget {
  const DefaultColorSettingsList({
    super.key,
    required this.colors,
    required this.onRecolor,
    required this.onDelete,
    required this.onCreate,
  });

  final List<DefaultColor> colors;
  final Future<void> Function(DefaultColor color, int argb) onRecolor;
  final Future<void> Function(DefaultColor color) onDelete;
  final Future<void> Function(int argb) onCreate;

  Future<void> _pick(BuildContext context, DefaultColor color) async {
    final argb = await showArgbColorPicker(context, initialArgb: color.argb);
    if (argb == null) return;
    await onRecolor(color, argb);
  }

  Future<void> _create(BuildContext context) async {
    final argb = await showArgbColorPicker(
      context,
      initialArgb: kFallbackArgb,
    );
    if (argb == null) return;
    await onCreate(argb);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('默认色', style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _create(context),
              icon: const Icon(Icons.add),
              label: const Text('新建'),
            ),
          ],
        ),
        for (final color in colors)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                RectSwatch(
                  argb: color.argb,
                  selected: color.isCurrent,
                  onTap: () => _pick(context, color),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => onDelete(color),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
