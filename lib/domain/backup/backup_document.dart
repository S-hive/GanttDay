import '../models/app_settings.dart';
import '../models/color_swatch.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../gantt/swatch_resolve.dart';
import '../time/wall_clock.dart';

class BackupDocument {
  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.tasks,
    required this.tags,
    required this.settings,
    required this.colorSwatches,
  });

  final int version;
  final WallMinutes exportedAt;
  final List<Task> tasks;
  final List<Tag> tags;
  final AppSettings settings;
  final List<ColorSwatch> colorSwatches;

  Map<String, Object?> toJson() => {
        'version': version,
        'exportedAt': exportedAt,
        'color_swatches': [for (final s in colorSwatches) _swatchToJson(s)],
        'tasks': [for (final t in tasks) _taskToJson(t)],
        'tags': [
          for (final t in tags)
            {
              'id': t.id,
              'name': t.name,
              'swatch_id': t.swatchId,
            }
        ],
        'settings': {
          'visible_start_hour': settings.visibleStartHour,
          'visible_end_hour': settings.visibleEndHour,
          'urgency_window_days': settings.urgencyWindowDays,
        },
      };

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

  static ColorSwatch _swatchFromJson(Map<String, Object?> r) {
    return ColorSwatch(
      id: r['id'] as String,
      name: r['name'] as String,
      argb: r['argb'] as int,
      hue: r['hue'] as int,
      saturation: (r['saturation'] as num).toDouble(),
      lightness: (r['lightness'] as num).toDouble(),
      isDefault: r['is_default'] == true || r['is_default'] == 1,
      sortOrder: r['sort_order'] as int,
      slate: r['slate'] == true || r['slate'] == 1,
    );
  }

  static Map<String, Object?> _taskToJson(Task t) => {
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

    final swatchesRaw = json['color_swatches'];
    final swatches = swatchesRaw is List
        ? [
            for (final r in swatchesRaw)
              _swatchFromJson(Map<String, Object?>.from(r as Map))
          ]
        : const <ColorSwatch>[];

    return BackupDocument(
      version: version,
      exportedAt: exportedAt,
      colorSwatches: swatches,
      tasks: [
        for (final r in tasksRaw)
          _taskFromJson(
            Map<String, Object?>.from(r as Map),
            version: version,
          )
      ],
      tags: [
        for (final r in tagsRaw)
          _tagFromJson(
            Map<String, Object?>.from(r as Map),
            version: version,
          )
      ],
      settings: AppSettings(
        visibleStartHour: (settingsRaw['visible_start_hour'] as int?) ?? 8,
        visibleEndHour: (settingsRaw['visible_end_hour'] as int?) ?? 22,
        urgencyWindowDays: (settingsRaw['urgency_window_days'] as int?) ?? 7,
      ),
    );
  }

  static Tag _tagFromJson(Map<String, Object?> r, {required int version}) {
    final swatchId = r['swatch_id'];
    if (swatchId is String) {
      return Tag(
        id: r['id'] as String,
        name: r['name'] as String,
        swatchId: swatchId,
      );
    }
    if (version == 1 && r['hue'] is int) {
      return Tag(
        id: r['id'] as String,
        name: r['name'] as String,
        swatchId: swatchIdForHue(r['hue'] as int),
      );
    }
    throw const FormatException('missing tag swatch_id');
  }

  static Task _taskFromJson(Map<String, Object?> r, {required int version}) {
    final autoId = r['auto_swatch_id'];
    if (autoId is String) {
      final overrideId = r['override_swatch_id'];
      return Task(
        id: r['id'] as String,
        title: r['title'] as String,
        plannedStart: r['planned_start'] as int,
        plannedEnd: r['planned_end'] as int,
        actualStart: r['actual_start'] as int?,
        actualEnd: r['actual_end'] as int?,
        isDone: r['is_done'] == true || r['is_done'] == 1,
        primaryTagId: r['primary_tag_id'] as String?,
        autoSwatchId: autoId,
        overrideSwatchId: overrideId is String ? overrideId : null,
        notes: r['notes'] as String?,
        createdAt: r['created_at'] as int,
      );
    }
    if (version == 1 && r['auto_hue'] is int) {
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
    throw const FormatException('missing task auto_swatch_id');
  }
}

/// Per-task tag ids carried alongside the backup for import.
class BackupTaskTags {
  const BackupTaskTags(this.taskId, this.tagIds);
  final String taskId;
  final List<String> tagIds;
}
