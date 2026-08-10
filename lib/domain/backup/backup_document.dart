import '../../domain/gantt/swatch_resolve.dart';
import '../models/app_settings.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../time/wall_clock.dart';

class BackupDocument {
  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.tasks,
    required this.tags,
    required this.settings,
  });

  final int version;
  final WallMinutes exportedAt;
  final List<Task> tasks;
  final List<Tag> tags;
  final AppSettings settings;

  Map<String, Object?> toJson() => {
        'version': version,
        'exportedAt': exportedAt,
        'tasks': [for (final t in tasks) _taskToJson(t)],
        'tags': [
          for (final t in tags)
            {
              'id': t.id,
              'name': t.name,
              'hue': hueForSwatchId(t.swatchId),
            }
        ],
        'settings': {
          'visible_start_hour': settings.visibleStartHour,
          'visible_end_hour': settings.visibleEndHour,
          'urgency_window_days': settings.urgencyWindowDays,
        },
      };

  static Map<String, Object?> _taskToJson(Task t) => {
        'id': t.id,
        'title': t.title,
        'planned_start': t.plannedStart,
        'planned_end': t.plannedEnd,
        'actual_start': t.actualStart,
        'actual_end': t.actualEnd,
        'is_done': t.isDone,
        'primary_tag_id': t.primaryTagId,
        'auto_hue': hueForSwatchId(t.autoSwatchId),
        'override_hue': t.overrideSwatchId != null
            ? hueForSwatchId(t.overrideSwatchId!)
            : null,
        'notes': t.notes,
        'created_at': t.createdAt,
      };

  static BackupDocument fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version is! int) {
      throw const FormatException('missing version');
    }
    final exportedAt = json['exportedAt'];
    if (exportedAt is! int) {
      throw const FormatException('missing exportedAt');
    }
    final tasksRaw = json['tasks'];
    final tagsRaw = json['tags'];
    final settingsRaw = json['settings'];
    if (tasksRaw is! List || tagsRaw is! List || settingsRaw is! Map) {
      throw const FormatException('missing tasks/tags/settings');
    }
    return BackupDocument(
      version: version,
      exportedAt: exportedAt,
      tasks: [
        for (final r in tasksRaw)
          _taskFromJson(Map<String, Object?>.from(r as Map))
      ],
      tags: [
        for (final r in tagsRaw)
          Tag(
            id: (r as Map)['id'] as String,
            name: r['name'] as String,
            swatchId: swatchIdForHue(r['hue'] as int),
          )
      ],
      settings: AppSettings(
        visibleStartHour: (settingsRaw['visible_start_hour'] as int?) ?? 8,
        visibleEndHour: (settingsRaw['visible_end_hour'] as int?) ?? 22,
        urgencyWindowDays: (settingsRaw['urgency_window_days'] as int?) ?? 7,
      ),
    );
  }

  static Task _taskFromJson(Map<String, Object?> r) {
    return Task(
      id: r['id'] as String,
      title: r['title'] as String,
      plannedStart: r['planned_start'] as int,
      plannedEnd: r['planned_end'] as int,
      actualStart: r['actual_start'] as int?,
      actualEnd: r['actual_end'] as int?,
      isDone: r['is_done'] == true || r['is_done'] == 1,
      primaryTagId: r['primary_tag_id'] as String?,
      autoSwatchId: swatchIdForHue(r['auto_hue'] as int),
      overrideSwatchId: r['override_hue'] != null
          ? swatchIdForHue(r['override_hue'] as int)
          : null,
      notes: r['notes'] as String?,
      createdAt: r['created_at'] as int,
    );
  }
}

/// Per-task tag ids carried alongside the backup for import.
class BackupTaskTags {
  const BackupTaskTags(this.taskId, this.tagIds);
  final String taskId;
  final List<String> tagIds;
}
