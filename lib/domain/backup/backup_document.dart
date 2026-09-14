import '../models/app_settings.dart';
import '../models/default_color.dart';
import '../models/tag.dart';
import '../models/task.dart';
import '../time/wall_clock.dart';

class BackupDocument {
  const BackupDocument({
    required this.version,
    required this.exportedAt,
    required this.tasks,
    required this.tags,
    required this.defaultColors,
    required this.settings,
  });

  final int version;
  final WallMinutes exportedAt;
  final List<Task> tasks;
  final List<Tag> tags;
  final List<DefaultColor> defaultColors;
  final AppSettings settings;

  Map<String, Object?> toJson() => {
        'version': version,
        'exportedAt': exportedAt,
        'default_colors': [
          for (final c in defaultColors) _defaultToJson(c),
        ],
        'tasks': [for (final t in tasks) _taskToJson(t)],
        'tags': [for (final t in tags) _tagToJson(t)],
        'settings': {
          'visible_start_hour': settings.visibleStartHour,
          'visible_end_hour': settings.visibleEndHour,
          'urgency_window_days': settings.urgencyWindowDays,
        },
      };

  static Map<String, Object?> _tagToJson(Tag t) => {
        'id': t.id,
        'name': t.name,
        'argb': t.argb,
        'sort_order': t.sortOrder,
      };

  static Map<String, Object?> _defaultToJson(DefaultColor c) => {
        'id': c.id,
        'argb': c.argb,
        'is_current': c.isCurrent,
        'sort_order': c.sortOrder,
      };

  static Map<String, Object?> _taskToJson(Task t) => {
        'id': t.id,
        'title': t.title,
        'planned_start': t.plannedStart,
        'planned_end': t.plannedEnd,
        'actual_start': t.actualStart,
        'actual_end': t.actualEnd,
        'is_done': t.isDone,
        'tag_id': t.tagId,
        'override_argb': t.overrideArgb,
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
    final defaultsRaw = json['default_colors'];
    if (tasksRaw is! List ||
        tagsRaw is! List ||
        settingsRaw is! Map ||
        defaultsRaw is! List) {
      throw const FormatException('missing tasks/tags/default_colors/settings');
    }

    return BackupDocument(
      version: version,
      exportedAt: exportedAt,
      defaultColors: [
        for (final r in defaultsRaw)
          _defaultFromJson(Map<String, Object?>.from(r as Map))
      ],
      tasks: [
        for (final r in tasksRaw)
          _taskFromJson(Map<String, Object?>.from(r as Map))
      ],
      tags: [
        for (final r in tagsRaw)
          _tagFromJson(Map<String, Object?>.from(r as Map))
      ],
      settings: AppSettings(
        visibleStartHour: (settingsRaw['visible_start_hour'] as int?) ?? 8,
        visibleEndHour: (settingsRaw['visible_end_hour'] as int?) ?? 22,
        urgencyWindowDays: (settingsRaw['urgency_window_days'] as int?) ?? 7,
      ),
    );
  }

  static Tag _tagFromJson(Map<String, Object?> r) {
    return Tag(
      id: r['id'] as String,
      name: r['name'] as String,
      argb: r['argb'] as int,
      sortOrder: r['sort_order'] as int,
    );
  }

  static DefaultColor _defaultFromJson(Map<String, Object?> r) {
    return DefaultColor(
      id: r['id'] as String,
      argb: r['argb'] as int,
      sortOrder: r['sort_order'] as int,
      isCurrent: r['is_current'] == true || r['is_current'] == 1,
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
      tagId: r['tag_id'] as String?,
      overrideArgb: r['override_argb'] as int?,
      notes: r['notes'] as String?,
      createdAt: r['created_at'] as int,
    );
  }
}
