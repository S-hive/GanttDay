import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/app_settings.dart';
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

  static const int supportedVersion = 1;

  Future<String> exportJson() async {
    final allTasks = await tasks.watchTasksOverlapping(0, 1 << 30).first;
    final tags = await tasks.listTags();
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
        'auto_hue': t.autoHue,
        'override_hue': t.overrideHue,
        'notes': t.notes,
        'created_at': t.createdAt,
        'tag_ids': tagIds,
      });
    }

    final doc = {
      'version': supportedVersion,
      'exportedAt': WallClock.now(),
      'tasks': tasksJson,
      'tags': [
        for (final t in tags) {'id': t.id, 'name': t.name, 'hue': t.hue}
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
    if (version != supportedVersion) {
      problems.add('不支持的版本号: $version（需要 $supportedVersion）');
    }

    final tasksRaw = map['tasks'];
    final tagsRaw = map['tags'];
    final settingsRaw = map['settings'];
    if (tasksRaw is! List) problems.add('缺少 tasks 数组');
    if (tagsRaw is! List) problems.add('缺少 tags 数组');
    if (settingsRaw is! Map) problems.add('缺少 settings 对象');

    final parsedTasks = <Task>[];
    final taskTagIds = <String, List<String>>{};
    if (tasksRaw is List) {
      for (var i = 0; i < tasksRaw.length; i++) {
        final row = tasksRaw[i];
        if (row is! Map) {
          problems.add('tasks[$i] 不是对象');
          continue;
        }
        final m = Map<String, Object?>.from(row);
        final task = _parseTask(m, i, problems);
        if (task != null) {
          parsedTasks.add(task);
          final ids = m['tag_ids'];
          if (ids is List) {
            taskTagIds[task.id] = [for (final x in ids) '$x'];
          }
        }
      }
    }

    final parsedTags = <Tag>[];
    if (tagsRaw is List) {
      for (var i = 0; i < tagsRaw.length; i++) {
        final row = tagsRaw[i];
        if (row is! Map) {
          problems.add('tags[$i] 不是对象');
          continue;
        }
        final m = Map<String, Object?>.from(row);
        final id = m['id'];
        final name = m['name'];
        final hue = m['hue'];
        if (id is! String || id.isEmpty) {
          problems.add('tags[$i]: 缺少 id');
          continue;
        }
        if (name is! String || name.isEmpty) {
          problems.add('tags[$i]: 缺少 name');
          continue;
        }
        if (hue is! int) {
          problems.add('tags[$i]: 缺少 hue');
          continue;
        }
        parsedTags.add(Tag(id: id, name: name, hue: hue));
      }
    }

    AppSettings? parsedSettings;
    if (settingsRaw is Map) {
      final s = Map<String, Object?>.from(settingsRaw);
      final start = s['visible_start_hour'];
      final end = s['visible_end_hour'];
      final days = s['urgency_window_days'];
      if (start is! int || end is! int || days is! int) {
        problems.add('settings 字段类型非法');
      } else if (start >= end || days < 1) {
        problems.add('settings 可视时段或紧迫窗口非法');
      } else {
        parsedSettings = AppSettings(
          visibleStartHour: start,
          visibleEndHour: end,
          urgencyWindowDays: days,
        );
      }
    }

    if (problems.isNotEmpty) {
      throw BackupValidationException(problems);
    }

    var importedTasks = 0;
    var importedTags = 0;
    var skipped = 0;

    await db.transaction((txn) async {
      for (final tag in parsedTags) {
        final existing = await txn.query(
          'tag',
          where: 'id = ?',
          whereArgs: [tag.id],
        );
        if (existing.isEmpty) {
          await txn.insert('tag', {
            'id': tag.id,
            'name': tag.name,
            'hue': tag.hue,
          });
          importedTags++;
        }
      }

      for (final task in parsedTasks) {
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
          'auto_hue': task.autoHue,
          'override_hue': task.overrideHue,
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

      final s = parsedSettings!;
      Future<void> put(String key, Object value) => txn.insert(
            'setting',
            {'key': key, 'value': '$value'},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
      await put('visible_start_hour', s.visibleStartHour);
      await put('visible_end_hour', s.visibleEndHour);
      await put('urgency_window_days', s.urgencyWindowDays);
    });

    if (tasks is SqliteTaskRepository) {
      (tasks as SqliteTaskRepository).notifyChanged();
    }
    await settings.write(parsedSettings!);

    return BackupImportResult(
      importedTasks: importedTasks,
      importedTags: importedTags,
      skippedDuplicates: skipped,
    );
  }

  Task? _parseTask(Map<String, Object?> m, int i, List<String> problems) {
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
    return Task(
      id: id,
      title: title,
      plannedStart: start,
      plannedEnd: end,
      actualStart: m['actual_start'] as int?,
      actualEnd: m['actual_end'] as int?,
      isDone: m['is_done'] == true || m['is_done'] == 1,
      primaryTagId: m['primary_tag_id'] as String?,
      autoHue: autoHue,
      overrideHue: m['override_hue'] as int?,
      notes: m['notes'] as String?,
      createdAt: createdAt,
    );
  }
}
