import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

import '../../domain/gantt/argb_color.dart';
import '../../domain/gantt/color_palette.dart';
import '../../domain/gantt/factory_swatches.dart';
import '../../domain/gantt/swatch_resolve.dart';
import '../../domain/models/app_settings.dart';
import '../../domain/models/color_swatch.dart';
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

  static const int supportedVersion = 2;

  Future<String> exportJson() async {
    final allTasks = await tasks.watchTasksOverlapping(0, 1 << 30).first;
    final tags = await tasks.listTags();
    final swatches = await tasks.listSwatches();
    final appSettings = await settings.read();

    final tasksJson = <Map<String, Object?>>[];
    for (final t in allTasks) {
      final tagIds = await tasks.tagIdsForTask(t.id);
      tasksJson.add({
        'id': t.id,
        'title': t.title,
        'planned_start': t.plannedStart,
        'planned_end': t.plannedEnd,
        'actual_start': t.actualStart,
        'actual_end': t.actualEnd,
        'is_done': t.isDone,
        'primary_tag_id': t.primaryTagId,
        'auto_swatch_id': t.autoSwatchId,
        'override_swatch_id': t.overrideSwatchId,
        'notes': t.notes,
        'created_at': t.createdAt,
        'tag_ids': tagIds,
      });
    }

    final doc = {
      'version': supportedVersion,
      'exportedAt': WallClock.now(),
      'color_swatches': [for (final s in swatches) _swatchToJson(s)],
      'tasks': tasksJson,
      'tags': [
        for (final t in tags)
          {
            'id': t.id,
            'name': t.name,
            'swatch_id': t.swatchId,
          }
      ],
      'settings': {
        'visible_start_hour': appSettings.visibleStartHour,
        'visible_end_hour': appSettings.visibleEndHour,
        'urgency_window_days': appSettings.urgencyWindowDays,
      },
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Future<BackupImportResult> importJson(String text) async {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw BackupValidationException(['根节点必须是 JSON 对象']);
    }
    final map = Map<String, Object?>.from(decoded);
    final problems = <String>[];

    final version = map['version'];
    if (version is! int || (version != 1 && version != supportedVersion)) {
      problems.add('不支持的版本号: $version（需要 1 或 $supportedVersion）');
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

    if (version == 1) {
      return _importV1(
        tasksRaw as List,
        tagsRaw as List,
        Map<String, Object?>.from(settingsRaw as Map),
      );
    }
    return _importV2(
      map,
      tasksRaw as List,
      tagsRaw as List,
      Map<String, Object?>.from(settingsRaw as Map),
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

    final swatchIds = {for (final s in parsedSwatches) s.id};

    final parsedTasks = <Task>[];
    final taskTagIds = <String, List<String>>{};
    for (var i = 0; i < tasksRaw.length; i++) {
      final row = tasksRaw[i];
      if (row is! Map) {
        problems.add('tasks[$i] 不是对象');
        continue;
      }
      final m = Map<String, Object?>.from(row);
      final task = _parseTaskV2(m, i, swatchIds, problems);
      if (task != null) {
        parsedTasks.add(task);
        final ids = m['tag_ids'];
        if (ids is List) {
          taskTagIds[task.id] = [for (final x in ids) '$x'];
        }
      }
    }

    final parsedTags = <Tag>[];
    for (var i = 0; i < tagsRaw.length; i++) {
      final row = tagsRaw[i];
      if (row is! Map) {
        problems.add('tags[$i] 不是对象');
        continue;
      }
      final m = Map<String, Object?>.from(row);
      final tag = _parseTagV2(m, i, swatchIds, problems);
      if (tag != null) parsedTags.add(tag);
    }

    final parsedSettings = _parseSettings(settingsRaw, problems);

    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    return _writeImport(
      swatches: parsedSwatches,
      tags: parsedTags,
      tasks: parsedTasks,
      taskTagIds: taskTagIds,
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
      final tag = _parseTagV1(Map<String, Object?>.from(row), i, resolver, problems);
      if (tag != null) parsedTags.add(tag);
    }

    final parsedTasks = <Task>[];
    final taskTagIds = <String, List<String>>{};
    for (var i = 0; i < tasksRaw.length; i++) {
      final row = tasksRaw[i];
      if (row is! Map) {
        problems.add('tasks[$i] 不是对象');
        continue;
      }
      final m = Map<String, Object?>.from(row);
      final task = _parseTaskV1(m, i, resolver, problems);
      if (task != null) {
        parsedTasks.add(task);
        final ids = m['tag_ids'];
        if (ids is List) {
          taskTagIds[task.id] = [for (final x in ids) '$x'];
        }
      }
    }

    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    return _writeImport(
      swatches: resolver.customSwatches,
      tags: parsedTags,
      tasks: parsedTasks,
      taskTagIds: taskTagIds,
      settings: parsedSettings!,
      ensureFactorySwatches: true,
    );
  }

  Future<BackupImportResult> _writeImport({
    required List<ColorSwatch> swatches,
    required List<Tag> tags,
    required List<Task> tasks,
    required Map<String, List<String>> taskTagIds,
    required AppSettings settings,
    bool ensureFactorySwatches = false,
  }) async {
    var importedTasks = 0;
    var importedTags = 0;
    var skipped = 0;

    await db.transaction((txn) async {
      if (ensureFactorySwatches) {
        await _ensureFactorySwatches(txn);
      }
      for (final swatch in swatches) {
        await txn.insert(
          'color_swatch',
          _rowFromSwatch(swatch),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

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
            'swatch_id': tag.swatchId,
          });
          importedTags++;
        }
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
          'primary_tag_id': task.primaryTagId,
          'auto_swatch_id': task.autoSwatchId,
          'override_swatch_id': task.overrideSwatchId,
          'notes': task.notes,
          'created_at': task.createdAt,
        });
        for (final tagId in taskTagIds[task.id] ?? const <String>[]) {
          await txn.insert('task_tag', {
            'task_id': task.id,
            'tag_id': tagId,
          });
        }
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
    Set<String> swatchIds,
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
    if (!swatchIds.contains(swatchId)) {
      problems.add('tags[$i]: swatch_id 不存在: $swatchId');
      return null;
    }
    return Tag(id: id, name: name, swatchId: swatchId);
  }

  Task? _parseTaskV2(
    Map<String, Object?> m,
    int i,
    Set<String> swatchIds,
    List<String> problems,
  ) {
    final id = m['id'];
    final title = m['title'];
    final start = m['planned_start'];
    final end = m['planned_end'];
    final autoSwatchId = m['auto_swatch_id'];
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
    if (autoSwatchId is! String || autoSwatchId.isEmpty) {
      problems.add('tasks[$i]: 缺少 auto_swatch_id');
      return null;
    }
    if (!swatchIds.contains(autoSwatchId)) {
      problems.add('tasks[$i]: auto_swatch_id 不存在: $autoSwatchId');
      return null;
    }
    final overrideId = m['override_swatch_id'];
    if (overrideId != null) {
      if (overrideId is! String || overrideId.isEmpty) {
        problems.add('tasks[$i]: override_swatch_id 非法');
        return null;
      }
      if (!swatchIds.contains(overrideId)) {
        problems.add('tasks[$i]: override_swatch_id 不存在: $overrideId');
        return null;
      }
    }
    if (createdAt is! int) {
      problems.add('tasks[$i]: created_at 非法');
      return null;
    }
    return Task(
      id: id,
      title: title,
      plannedStart: start,
      plannedEnd: end,
      actualStart: m['actual_start'] as int?,
      actualEnd: m['actual_end'] as int?,
      isDone: m['is_done'] == true || m['is_done'] == 1,
      primaryTagId: m['primary_tag_id'] as String?,
      autoSwatchId: autoSwatchId,
      overrideSwatchId: overrideId as String?,
      notes: m['notes'] as String?,
      createdAt: createdAt,
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
    return Tag(id: id, name: name, swatchId: resolver.resolve(hue));
  }

  Task? _parseTaskV1(
    Map<String, Object?> m,
    int i,
    _HueToSwatchResolver resolver,
    List<String> problems,
  ) {
    final id = m['id'];
    final title = m['title'];
    final start = m['planned_start'];
    final end = m['planned_end'];
    final autoHue = m['auto_hue'];
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
    if (autoHue is! int || createdAt is! int) {
      problems.add('tasks[$i]: auto_hue / created_at 非法');
      return null;
    }
    final autoSwatchId = resolver.resolve(autoHue);
    final overrideHue = m['override_hue'];
    final overrideSwatchId =
        overrideHue != null ? resolver.resolve(overrideHue as int) : null;
    return Task(
      id: id,
      title: title,
      plannedStart: start,
      plannedEnd: end,
      actualStart: m['actual_start'] as int?,
      actualEnd: m['actual_end'] as int?,
      isDone: m['is_done'] == true || m['is_done'] == 1,
      primaryTagId: m['primary_tag_id'] as String?,
      autoSwatchId: autoSwatchId,
      overrideSwatchId: overrideSwatchId,
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

  Future<void> _ensureFactorySwatches(DatabaseExecutor txn) async {
    for (final s in kFactoryColorSwatches) {
      await txn.insert(
        'color_swatch',
        _rowFromSwatch(s),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  static Map<String, Object?> _swatchToJson(ColorSwatch s) => {
        'id': s.id,
        'name': s.name,
        'argb': s.argb,
        'hue': s.hue,
        'saturation': s.saturation,
        'lightness': s.lightness,
        'is_default': s.isDefault,
        'sort_order': s.sortOrder,
        'slate': s.slate,
      };

  static Map<String, Object?> _rowFromSwatch(ColorSwatch s) => {
        'id': s.id,
        'name': s.name,
        'argb': s.argb,
        'hue': s.hue,
        'saturation': s.saturation,
        'lightness': s.lightness,
        'is_default': s.isDefault ? 1 : 0,
        'sort_order': s.sortOrder,
        'slate': s.slate ? 1 : 0,
      };
}

const _customSwatchName = '自定义色';

class _HueToSwatchResolver {
  _HueToSwatchResolver() {
    for (final s in kFactoryColorSwatches) {
      _hueToId[s.hue] = s.id;
    }
  }

  final _uuid = const Uuid();
  final Map<int, String> _hueToId = {};
  final Map<int, ColorSwatch> _customByHue = {};
  var _nextSortOrder = kFactoryColorSwatches.length;

  List<ColorSwatch> get customSwatches => _customByHue.values.toList();

  String resolve(int hue) {
    final cached = _hueToId[hue];
    if (cached != null) return cached;

    final id = _uuid.v4();
    final argb = ArgbColor.fromHsl(
      hue.toDouble(),
      kPalettePreviewSaturation,
      kPalettePreviewLightness,
    );
    final swatch = colorSwatchFromArgb(
      id: id,
      name: _customSwatchName,
      argb: argb,
      sortOrder: _nextSortOrder++,
    );
    _hueToId[hue] = id;
    _customByHue[hue] = swatch;
    return id;
  }
}
