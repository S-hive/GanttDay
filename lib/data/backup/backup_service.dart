import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../domain/backup/backup_document.dart';
import '../../domain/gantt/argb_color.dart';
import '../../domain/gantt/color_palette.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/color_swatch.dart';
import '../../domain/models/default_color.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../../platform/settings_store.dart';
import '../../platform/task_repository.dart';
import '../sqlite/sqlite_task_repository.dart';

class BackupValidationException implements Exception {
  BackupValidationException(this.problems);
  final List<String> problems;

  @override
  String toString() => 'BackupValidationException: ${problems.join('; ')}';
}

class BackupImportResult {
  const BackupImportResult({
    required this.importedTasks,
    required this.importedTags,
    required this.skippedDuplicates,
  });

  final int importedTasks;
  final int importedTags;
  final int skippedDuplicates;
}

class BackupService {
  BackupService(this.db, this.tasks, this.settings);

  final Database db;
  final TaskRepository tasks;
  final SettingsStore settings;

  static const int supportedVersion = 3;

  Future<String> exportJson() async {
    final allTasks = await tasks.watchTasksOverlapping(0, 1 << 30).first;
    final tags = await tasks.listTags();
    final defaults = await tasks.listDefaultColors();
    final appSettings = await settings.read();
    final doc = BackupDocument(
      version: supportedVersion,
      exportedAt: WallClock.now(),
      tasks: allTasks,
      tags: tags,
      defaultColors: defaults,
      settings: appSettings,
    );
    return const JsonEncoder.withIndent('  ').convert(doc.toJson());
  }

  Future<BackupImportResult> importJson(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw BackupValidationException(['根节点必须是 JSON 对象']);
    }
    final map = Map<String, Object?>.from(decoded);
    final problems = <String>[];

    final version = map['version'];
    if (version is! int || (version != 1 && version != 2 && version != 3)) {
      problems.add('不支持的版本号: $version（需要 1、2 或 $supportedVersion）');
    }

    final tasksRaw = map['tasks'];
    final tagsRaw = map['tags'];
    final settingsRaw = map['settings'];
    if (tasksRaw is! List) problems.add('缺少 tasks 数组');
    if (tagsRaw is! List) problems.add('缺少 tags 数组');
    if (settingsRaw is! Map) problems.add('缺少 settings 对象');

    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    final settingsMap = Map<String, Object?>.from(settingsRaw as Map);
    if (version == 1) {
      return _importV1(tasksRaw as List, tagsRaw as List, settingsMap);
    }
    if (version == 2) {
      return _importV2(map, tasksRaw as List, tagsRaw as List, settingsMap);
    }
    return _importV3(map, tasksRaw as List, tagsRaw as List, settingsMap);
  }

  Future<BackupImportResult> _importV3(
    Map<String, Object?> map,
    List tasksRaw,
    List tagsRaw,
    Map<String, Object?> settingsRaw,
  ) async {
    final problems = <String>[];
    final defaultsRaw = map['default_colors'];
    if (defaultsRaw is! List) {
      problems.add('缺少 default_colors 数组');
    }

    final parsedDefaults = <DefaultColor>[];
    if (defaultsRaw is List) {
      for (var i = 0; i < defaultsRaw.length; i++) {
        final row = defaultsRaw[i];
        if (row is! Map) {
          problems.add('default_colors[$i] 不是对象');
          continue;
        }
        final c = _parseDefaultColor(Map<String, Object?>.from(row), i, problems);
        if (c != null) parsedDefaults.add(c);
      }
    }

    final parsedTags = <Tag>[];
    final tagIds = <String>{};
    for (var i = 0; i < tagsRaw.length; i++) {
      final row = tagsRaw[i];
      if (row is! Map) {
        problems.add('tags[$i] 不是对象');
        continue;
      }
      final tag = _parseTagV3(Map<String, Object?>.from(row), i, problems);
      if (tag != null) {
        parsedTags.add(tag);
        tagIds.add(tag.id);
      }
    }

    final parsedTasks = <Task>[];
    for (var i = 0; i < tasksRaw.length; i++) {
      final row = tasksRaw[i];
      if (row is! Map) {
        problems.add('tasks[$i] 不是对象');
        continue;
      }
      final task = _parseTaskV3(
        Map<String, Object?>.from(row),
        i,
        tagIds,
        problems,
      );
      if (task != null) parsedTasks.add(task);
    }

    final parsedSettings = _parseSettings(settingsRaw, problems);
    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    return _writeImport(
      tags: parsedTags,
      defaultColors: parsedDefaults,
      tasks: parsedTasks,
      settings: parsedSettings!,
    );
  }

  Future<BackupImportResult> _importV2(
    Map<String, Object?> map,
    List tasksRaw,
    List tagsRaw,
    Map<String, Object?> settingsRaw,
  ) async {
    final problems = <String>[];
    final swatchesRaw = map['color_swatches'];
    if (swatchesRaw is! List) {
      problems.add('缺少 color_swatches 数组');
    }

    final parsedSwatches = <ColorSwatch>[];
    if (swatchesRaw is List) {
      for (var i = 0; i < swatchesRaw.length; i++) {
        final row = swatchesRaw[i];
        if (row is! Map) {
          problems.add('color_swatches[$i] 不是对象');
          continue;
        }
        final s = _parseSwatch(Map<String, Object?>.from(row), i, problems);
        if (s != null) parsedSwatches.add(s);
      }
    }
    final swatchById = {for (final s in parsedSwatches) s.id: s};

    final parsedTags = <Tag>[];
    for (var i = 0; i < tagsRaw.length; i++) {
      final row = tagsRaw[i];
      if (row is! Map) {
        problems.add('tags[$i] 不是对象');
        continue;
      }
      final tag = _parseTagV2(
        Map<String, Object?>.from(row),
        i,
        swatchById,
        problems,
      );
      if (tag != null) parsedTags.add(tag);
    }
    final tagIds = {for (final t in parsedTags) t.id};

    final parsedTasks = <Task>[];
    for (var i = 0; i < tasksRaw.length; i++) {
      final row = tasksRaw[i];
      if (row is! Map) {
        problems.add('tasks[$i] 不是对象');
        continue;
      }
      final task = _parseTaskV2(
        Map<String, Object?>.from(row),
        i,
        swatchById,
        tagIds,
        problems,
      );
      if (task != null) parsedTasks.add(task);
    }

    final parsedSettings = _parseSettings(settingsRaw, problems);
    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    return _writeImport(
      tags: parsedTags,
      defaultColors: _defaultsFromSwatches(parsedSwatches),
      tasks: parsedTasks,
      settings: parsedSettings!,
    );
  }

  Future<BackupImportResult> _importV1(
    List tasksRaw,
    List tagsRaw,
    Map<String, Object?> settingsRaw,
  ) async {
    final problems = <String>[];
    final parsedSettings = _parseSettings(settingsRaw, problems);
    final resolver = _HueToSwatchResolver();

    final parsedTags = <Tag>[];
    for (var i = 0; i < tagsRaw.length; i++) {
      final row = tagsRaw[i];
      if (row is! Map) {
        problems.add('tags[$i] 不是对象');
        continue;
      }
      final tag = _parseTagV1(
        Map<String, Object?>.from(row),
        i,
        resolver,
        problems,
      );
      if (tag != null) parsedTags.add(tag);
    }
    final tagIds = {for (final t in parsedTags) t.id};

    final parsedTasks = <Task>[];
    for (var i = 0; i < tasksRaw.length; i++) {
      final row = tasksRaw[i];
      if (row is! Map) {
        problems.add('tasks[$i] 不是对象');
        continue;
      }
      final task = _parseTaskV1(
        Map<String, Object?>.from(row),
        i,
        resolver,
        tagIds,
        problems,
      );
      if (task != null) parsedTasks.add(task);
    }

    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    final factoryDefault = kFactoryColorSwatches.firstWhere((s) => s.isDefault);
    return _writeImport(
      tags: parsedTags,
      defaultColors: [
        DefaultColor(
          id: const Uuid().v4(),
          argb: factoryDefault.argb,
          sortOrder: 0,
          isCurrent: true,
        ),
      ],
      settings: parsedSettings!,
      tasks: parsedTasks,
    );
  }

  List<DefaultColor> _defaultsFromSwatches(List<ColorSwatch> swatches) {
    final defaults = [
      for (final s in swatches)
        if (s.isDefault) s,
    ]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    if (defaults.isEmpty) {
      return [
        DefaultColor(
          id: const Uuid().v4(),
          argb: kFallbackArgb,
          sortOrder: 0,
          isCurrent: true,
        ),
      ];
    }
    return [
      for (var i = 0; i < defaults.length; i++)
        DefaultColor(
          id: const Uuid().v4(),
          argb: defaults[i].argb,
          sortOrder: i,
          isCurrent: i == 0,
        ),
    ];
  }

  Future<BackupImportResult> _writeImport({
    required List<Tag> tags,
    required List<DefaultColor> defaultColors,
    required List<Task> tasks,
    required AppSettings settings,
  }) async {
    var importedTasks = 0;
    var importedTags = 0;
    var skipped = 0;

    await db.transaction((txn) async {
      for (final tag in tags) {
        final existing = await txn.query(
          'tag',
          where: 'id = ?',
          whereArgs: [tag.id],
        );
        if (existing.isEmpty) {
          await txn.insert('tag', {
            'id': tag.id,
            'name': tag.name,
            'argb': tag.argb,
            'sort_order': tag.sortOrder,
          });
          importedTags++;
        }
      }

      await txn.delete('default_color');
      for (final color in defaultColors) {
        await txn.insert('default_color', {
          'id': color.id,
          'argb': color.argb,
          'is_current': color.isCurrent ? 1 : 0,
          'sort_order': color.sortOrder,
        });
      }

      for (final task in tasks) {
        final existing = await txn.query(
          'task',
          where: 'id = ?',
          whereArgs: [task.id],
        );
        if (existing.isNotEmpty) {
          skipped++;
          continue;
        }
        await txn.insert('task', {
          'id': task.id,
          'title': task.title,
          'planned_start': task.plannedStart,
          'planned_end': task.plannedEnd,
          'actual_start': task.actualStart,
          'actual_end': task.actualEnd,
          'is_done': task.isDone ? 1 : 0,
          'tag_id': task.tagId,
          'override_argb': task.overrideArgb,
          'notes': task.notes,
          'created_at': task.createdAt,
        });
        importedTasks++;
      }

      await _writeSettings(txn, settings);
    });

    if (this.tasks is SqliteTaskRepository) {
      (this.tasks as SqliteTaskRepository).notifyChanged();
    }
    await this.settings.write(settings);

    return BackupImportResult(
      importedTasks: importedTasks,
      importedTags: importedTags,
      skippedDuplicates: skipped,
    );
  }

  AppSettings? _parseSettings(
    Map<String, Object?> settingsRaw,
    List<String> problems,
  ) {
    final start = settingsRaw['visible_start_hour'];
    final end = settingsRaw['visible_end_hour'];
    final days = settingsRaw['urgency_window_days'];
    if (start is! int || end is! int || days is! int) {
      problems.add('settings 字段类型非法');
      return null;
    }
    if (start >= end || days < 1) {
      problems.add('settings 可视时段或紧迫窗口非法');
      return null;
    }
    return AppSettings(
      visibleStartHour: start,
      visibleEndHour: end,
      urgencyWindowDays: days,
    );
  }

  DefaultColor? _parseDefaultColor(
    Map<String, Object?> m,
    int i,
    List<String> problems,
  ) {
    final id = m['id'];
    final argb = m['argb'];
    final sortOrder = m['sort_order'];
    if (id is! String || id.isEmpty) {
      problems.add('default_colors[$i]: 缺少 id');
      return null;
    }
    if (argb is! int || sortOrder is! int) {
      problems.add('default_colors[$i]: 字段类型非法');
      return null;
    }
    return DefaultColor(
      id: id,
      argb: argb,
      sortOrder: sortOrder,
      isCurrent: m['is_current'] == true || m['is_current'] == 1,
    );
  }

  Tag? _parseTagV3(
    Map<String, Object?> m,
    int i,
    List<String> problems,
  ) {
    final id = m['id'];
    final name = m['name'];
    final argb = m['argb'];
    final sortOrder = m['sort_order'];
    if (id is! String || id.isEmpty) {
      problems.add('tags[$i]: 缺少 id');
      return null;
    }
    if (name is! String || name.isEmpty) {
      problems.add('tags[$i]: 缺少 name');
      return null;
    }
    if (argb is! int || sortOrder is! int) {
      problems.add('tags[$i]: 字段类型非法');
      return null;
    }
    return Tag(id: id, name: name, argb: argb, sortOrder: sortOrder);
  }

  Task? _parseTaskV3(
    Map<String, Object?> m,
    int i,
    Set<String> tagIds,
    List<String> problems,
  ) {
    final core = _parseTaskCore(m, i, problems);
    if (core == null) return null;
    final tagId = m['tag_id'];
    if (tagId != null) {
      if (tagId is! String || tagId.isEmpty) {
        problems.add('tasks[$i]: tag_id 非法');
        return null;
      }
      if (!tagIds.contains(tagId)) {
        problems.add('tasks[$i]: tag_id 不存在: $tagId');
        return null;
      }
    }
    final overrideArgb = m['override_argb'];
    if (overrideArgb != null && overrideArgb is! int) {
      problems.add('tasks[$i]: override_argb 非法');
      return null;
    }
    return Task(
      id: core.id,
      title: core.title,
      plannedStart: core.plannedStart,
      plannedEnd: core.plannedEnd,
      actualStart: core.actualStart,
      actualEnd: core.actualEnd,
      isDone: core.isDone,
      tagId: tagId as String?,
      overrideArgb: overrideArgb as int?,
      notes: core.notes,
      createdAt: core.createdAt,
    );
  }

  ColorSwatch? _parseSwatch(
    Map<String, Object?> m,
    int i,
    List<String> problems,
  ) {
    final id = m['id'];
    final name = m['name'];
    final argb = m['argb'];
    final hue = m['hue'];
    final saturation = m['saturation'];
    final lightness = m['lightness'];
    final sortOrder = m['sort_order'];
    if (id is! String || id.isEmpty) {
      problems.add('color_swatches[$i]: 缺少 id');
      return null;
    }
    if (name is! String || name.isEmpty) {
      problems.add('color_swatches[$i]: 缺少 name');
      return null;
    }
    if (argb is! int ||
        hue is! int ||
        saturation is! num ||
        lightness is! num ||
        sortOrder is! int) {
      problems.add('color_swatches[$i]: 字段类型非法');
      return null;
    }
    return ColorSwatch(
      id: id,
      name: name,
      argb: argb,
      hue: hue,
      saturation: saturation.toDouble(),
      lightness: lightness.toDouble(),
      isDefault: m['is_default'] == true || m['is_default'] == 1,
      sortOrder: sortOrder,
      slate: m['slate'] == true || m['slate'] == 1,
    );
  }

  Tag? _parseTagV2(
    Map<String, Object?> m,
    int i,
    Map<String, ColorSwatch> swatchById,
    List<String> problems,
  ) {
    final id = m['id'];
    final name = m['name'];
    final swatchId = m['swatch_id'];
    if (id is! String || id.isEmpty) {
      problems.add('tags[$i]: 缺少 id');
      return null;
    }
    if (name is! String || name.isEmpty) {
      problems.add('tags[$i]: 缺少 name');
      return null;
    }
    if (swatchId is! String || swatchId.isEmpty) {
      problems.add('tags[$i]: 缺少 swatch_id');
      return null;
    }
    final swatch = swatchById[swatchId];
    if (swatch == null) {
      problems.add('tags[$i]: swatch_id 不存在: $swatchId');
      return null;
    }
    return Tag(
      id: id,
      name: name,
      argb: swatch.argb,
      sortOrder: i,
    );
  }

  Task? _parseTaskV2(
    Map<String, Object?> m,
    int i,
    Map<String, ColorSwatch> swatchById,
    Set<String> tagIds,
    List<String> problems,
  ) {
    final core = _parseTaskCore(m, i, problems);
    if (core == null) return null;
    final autoSwatchId = m['auto_swatch_id'];
    if (autoSwatchId is! String || autoSwatchId.isEmpty) {
      problems.add('tasks[$i]: 缺少 auto_swatch_id');
      return null;
    }
    if (!swatchById.containsKey(autoSwatchId)) {
      problems.add('tasks[$i]: auto_swatch_id 不存在: $autoSwatchId');
      return null;
    }
    final overrideId = m['override_swatch_id'];
    int? overrideArgb;
    if (overrideId != null) {
      if (overrideId is! String || overrideId.isEmpty) {
        problems.add('tasks[$i]: override_swatch_id 非法');
        return null;
      }
      final override = swatchById[overrideId];
      if (override == null) {
        problems.add('tasks[$i]: override_swatch_id 不存在: $overrideId');
        return null;
      }
      overrideArgb = override.argb;
    }
    final primary = m['primary_tag_id'];
    String? tagId;
    if (primary is String && tagIds.contains(primary)) {
      tagId = primary;
    }
    return Task(
      id: core.id,
      title: core.title,
      plannedStart: core.plannedStart,
      plannedEnd: core.plannedEnd,
      actualStart: core.actualStart,
      actualEnd: core.actualEnd,
      isDone: core.isDone,
      tagId: tagId,
      overrideArgb: overrideArgb,
      notes: core.notes,
      createdAt: core.createdAt,
    );
  }

  Tag? _parseTagV1(
    Map<String, Object?> m,
    int i,
    _HueToSwatchResolver resolver,
    List<String> problems,
  ) {
    final id = m['id'];
    final name = m['name'];
    final hue = m['hue'];
    if (id is! String || id.isEmpty) {
      problems.add('tags[$i]: 缺少 id');
      return null;
    }
    if (name is! String || name.isEmpty) {
      problems.add('tags[$i]: 缺少 name');
      return null;
    }
    if (hue is! int) {
      problems.add('tags[$i]: 缺少 hue');
      return null;
    }
    final swatch = resolver.resolve(hue);
    return Tag(id: id, name: name, argb: swatch.argb, sortOrder: i);
  }

  Task? _parseTaskV1(
    Map<String, Object?> m,
    int i,
    _HueToSwatchResolver resolver,
    Set<String> tagIds,
    List<String> problems,
  ) {
    final core = _parseTaskCore(m, i, problems);
    if (core == null) return null;
    final autoHue = m['auto_hue'];
    final createdAt = m['created_at'];
    if (autoHue is! int || createdAt is! int) {
      problems.add('tasks[$i]: auto_hue / created_at 非法');
      return null;
    }
    resolver.resolve(autoHue);
    final overrideHue = m['override_hue'];
    int? overrideArgb;
    if (overrideHue != null) {
      if (overrideHue is! int) {
        problems.add('tasks[$i]: override_hue 非法');
        return null;
      }
      overrideArgb = resolver.resolve(overrideHue).argb;
    }
    final primary = m['primary_tag_id'];
    String? tagId;
    if (primary is String && tagIds.contains(primary)) {
      tagId = primary;
    }
    return Task(
      id: core.id,
      title: core.title,
      plannedStart: core.plannedStart,
      plannedEnd: core.plannedEnd,
      actualStart: core.actualStart,
      actualEnd: core.actualEnd,
      isDone: core.isDone,
      tagId: tagId,
      overrideArgb: overrideArgb,
      notes: core.notes,
      createdAt: createdAt,
    );
  }

  _TaskCore? _parseTaskCore(
    Map<String, Object?> m,
    int i,
    List<String> problems,
  ) {
    final id = m['id'];
    final title = m['title'];
    final start = m['planned_start'];
    final end = m['planned_end'];
    final createdAt = m['created_at'];
    if (id is! String || id.isEmpty) {
      problems.add('tasks[$i]: 缺少 id');
      return null;
    }
    if (title is! String || title.isEmpty) {
      problems.add('tasks[$i]: 缺少 title');
      return null;
    }
    if (start is! int || end is! int) {
      problems.add('tasks[$i]: 计划时间非法');
      return null;
    }
    if (end <= start) {
      problems.add('tasks[$i]: 结束时间不晚于开始时间');
      return null;
    }
    if (createdAt is! int) {
      problems.add('tasks[$i]: created_at 非法');
      return null;
    }
    return _TaskCore(
      id: id,
      title: title,
      plannedStart: start,
      plannedEnd: end,
      actualStart: m['actual_start'] as int?,
      actualEnd: m['actual_end'] as int?,
      isDone: m['is_done'] == true || m['is_done'] == 1,
      notes: m['notes'] as String?,
      createdAt: createdAt,
    );
  }

  Future<void> _writeSettings(DatabaseExecutor txn, AppSettings s) async {
    Future<void> put(String key, Object value) => txn.insert(
          'setting',
          {'key': key, 'value': '$value'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
    await put('visible_start_hour', s.visibleStartHour);
    await put('visible_end_hour', s.visibleEndHour);
    await put('urgency_window_days', s.urgencyWindowDays);
  }
}

class _TaskCore {
  const _TaskCore({
    required this.id,
    required this.title,
    required this.plannedStart,
    required this.plannedEnd,
    required this.actualStart,
    required this.actualEnd,
    required this.isDone,
    required this.notes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final int plannedStart;
  final int plannedEnd;
  final int? actualStart;
  final int? actualEnd;
  final bool isDone;
  final String? notes;
  final int createdAt;
}

const _customSwatchName = '自定义色';

class _HueToSwatchResolver {
  _HueToSwatchResolver() {
    for (final s in kFactoryColorSwatches) {
      _hueToSwatch[s.hue] = s;
    }
  }

  final _uuid = const Uuid();
  final Map<int, ColorSwatch> _hueToSwatch = {};
  var _nextSortOrder = kFactoryColorSwatches.length;

  ColorSwatch resolve(int hue) {
    final cached = _hueToSwatch[hue];
    if (cached != null) return cached;

    final argb = ArgbColor.fromHsl(
      hue.toDouble(),
      kPalettePreviewSaturation,
      kPalettePreviewLightness,
    );
    final hsl = ArgbColor.toHsl(argb);
    final swatch = ColorSwatch(
      id: _uuid.v4(),
      name: _customSwatchName,
      argb: argb,
      hue: hsl.hue.round() % 360,
      saturation: hsl.saturation,
      lightness: hsl.lightness,
      sortOrder: _nextSortOrder++,
    );
    _hueToSwatch[hue] = swatch;
    return swatch;
  }
}
