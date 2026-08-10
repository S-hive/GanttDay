import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/color_swatch.dart';
import '../../domain/models/tag.dart';
import '../../domain/models/task.dart';
import '../../domain/time/wall_clock.dart';
import '../../platform/task_repository.dart';

class SqliteTaskRepository implements TaskRepository {
  SqliteTaskRepository(this._db);

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  void _notify() => _changes.add(null);

  /// Used after bulk SQL writes (backup import) so watchers re-query.
  void notifyChanged() => _notify();

  Future<void> dispose() => _changes.close();

  @override
  Stream<List<Task>> watchTasksOverlapping(
      WallMinutes rangeStart, WallMinutes rangeEnd) {
    late StreamController<List<Task>> controller;
    StreamSubscription<void>? changeSub;

    Future<void> emit() async {
      final result = await _queryOverlapping(rangeStart, rangeEnd);
      if (!controller.isClosed) controller.add(result);
    }

    controller = StreamController<List<Task>>(
      onListen: () {
        emit();
        changeSub = _changes.stream.listen((_) => emit());
      },
      onCancel: () async {
        await changeSub?.cancel();
      },
    );
    return controller.stream;
  }

  Future<List<Task>> _queryOverlapping(
      WallMinutes rangeStart, WallMinutes rangeEnd) async {
    // Span overlap, not start-time containment — this is what makes an
    // overnight task show up on both of its days (spec section 4).
    final rows = await _db.query(
      'task',
      where: 'planned_start < ? AND planned_end > ?',
      whereArgs: [rangeEnd, rangeStart],
      orderBy: 'planned_start ASC',
    );
    return rows.map(_taskFromRow).toList();
  }

  @override
  Future<Task?> getById(String id) async {
    final rows = await _db.query('task', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _taskFromRow(rows.first);
  }

  @override
  Future<void> upsert(Task task) async {
    await _db.insert(
      'task',
      _rowFromTask(task),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<void> delete(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('task', where: 'id = ?', whereArgs: [id]);
      await txn.delete('task_tag', where: 'task_id = ?', whereArgs: [id]);
    });
    _notify();
  }

  @override
  Future<void> complete(
    String id, {
    required WallMinutes actualStart,
    required WallMinutes actualEnd,
  }) async {
    await _db.update(
      'task',
      {'is_done': 1, 'actual_start': actualStart, 'actual_end': actualEnd},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  @override
  Future<void> uncomplete(String id) async {
    await _db.update(
      'task',
      {'is_done': 0, 'actual_start': null, 'actual_end': null},
      where: 'id = ?',
      whereArgs: [id],
    );
    _notify();
  }

  @override
  Future<List<Tag>> listTags() async {
    final rows = await _db.query('tag', orderBy: 'name ASC');
    return rows
        .map((r) => Tag(
              id: r['id'] as String,
              name: r['name'] as String,
              swatchId: r['swatch_id'] as String,
            ))
        .toList();
  }

  @override
  Future<void> upsertTag(Tag tag) async {
    await _db.insert(
      'tag',
      {'id': tag.id, 'name': tag.name, 'swatch_id': tag.swatchId},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<void> deleteTag(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('tag', where: 'id = ?', whereArgs: [id]);
      await txn.delete('task_tag', where: 'tag_id = ?', whereArgs: [id]);
      // Tasks that pointed at this tag fall back to their stored auto hue.
      await txn.update(
        'task',
        {'primary_tag_id': null},
        where: 'primary_tag_id = ?',
        whereArgs: [id],
      );
    });
    _notify();
  }

  @override
  Future<void> setTaskTags(String taskId, List<String> tagIds) async {
    await _db.transaction((txn) async {
      await txn.delete('task_tag', where: 'task_id = ?', whereArgs: [taskId]);
      for (final tagId in tagIds) {
        await txn.insert('task_tag', {'task_id': taskId, 'tag_id': tagId});
      }
    });
    _notify();
  }

  @override
  Future<List<String>> tagIdsForTask(String taskId) async {
    final rows = await _db.query(
      'task_tag',
      columns: ['tag_id'],
      where: 'task_id = ?',
      whereArgs: [taskId],
    );
    return rows.map((r) => r['tag_id'] as String).toList();
  }

  @override
  Future<List<ColorSwatch>> listSwatches() async {
    final rows = await _db.query('color_swatch', orderBy: 'sort_order ASC');
    return rows.map(_swatchFromRow).toList();
  }

  @override
  Stream<List<ColorSwatch>> watchSwatches() {
    late StreamController<List<ColorSwatch>> controller;
    StreamSubscription<void>? changeSub;

    Future<void> emit() async {
      final result = await listSwatches();
      if (!controller.isClosed) controller.add(result);
    }

    controller = StreamController<List<ColorSwatch>>(
      onListen: () {
        emit();
        changeSub = _changes.stream.listen((_) => emit());
      },
      onCancel: () async {
        await changeSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<ColorSwatch> defaultSwatch() async {
    final rows =
        await _db.query('color_swatch', where: 'is_default = 1', limit: 1);
    if (rows.isEmpty) {
      throw StateError('No default color swatch');
    }
    return _swatchFromRow(rows.first);
  }

  @override
  Future<void> upsertSwatch(ColorSwatch swatch) async {
    await _db.transaction((txn) async {
      if (swatch.isDefault) {
        await txn.update('color_swatch', {'is_default': 0});
      }
      await txn.insert(
        'color_swatch',
        _rowFromSwatch(swatch),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notify();
  }

  @override
  Future<void> setDefaultSwatch(String id) async {
    final exists = await _db.query(
      'color_swatch',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (exists.isEmpty) {
      throw SwatchOperationException('Swatch not found: $id');
    }
    await _db.transaction((txn) async {
      await txn.update('color_swatch', {'is_default': 0});
      await txn.update(
        'color_swatch',
        {'is_default': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    _notify();
  }

  @override
  Future<void> deleteSwatch(String id, {required String rebindToId}) async {
    if (id == rebindToId) {
      throw SwatchOperationException('rebindToId must differ from deleted id');
    }

    final countRow = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM color_swatch',
    );
    final count = countRow.first['c'] as int;
    if (count <= 1) {
      throw SwatchOperationException('Cannot delete the last swatch');
    }

    final rebindExists = await _db.query(
      'color_swatch',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rebindToId],
      limit: 1,
    );
    if (rebindExists.isEmpty) {
      throw SwatchOperationException('Rebind target not found: $rebindToId');
    }

    final victim = await _db.query(
      'color_swatch',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (victim.isEmpty) {
      throw SwatchOperationException('Swatch not found: $id');
    }
    final wasDefault = (victim.first['is_default'] as int) != 0;

    await _db.transaction((txn) async {
      await txn.update(
        'task',
        {'auto_swatch_id': rebindToId},
        where: 'auto_swatch_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'task',
        {'override_swatch_id': rebindToId},
        where: 'override_swatch_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'tag',
        {'swatch_id': rebindToId},
        where: 'swatch_id = ?',
        whereArgs: [id],
      );
      await txn.delete('color_swatch', where: 'id = ?', whereArgs: [id]);
      if (wasDefault) {
        await txn.update('color_swatch', {'is_default': 0});
        await txn.update(
          'color_swatch',
          {'is_default': 1},
          where: 'id = ?',
          whereArgs: [rebindToId],
        );
      }
    });
    _notify();
  }

  ColorSwatch _swatchFromRow(Map<String, Object?> r) {
    return ColorSwatch(
      id: r['id'] as String,
      name: r['name'] as String,
      argb: r['argb'] as int,
      hue: r['hue'] as int,
      saturation: (r['saturation'] as num).toDouble(),
      lightness: (r['lightness'] as num).toDouble(),
      sortOrder: r['sort_order'] as int,
      isDefault: (r['is_default'] as int) != 0,
      slate: (r['slate'] as int) != 0,
    );
  }

  Map<String, Object?> _rowFromSwatch(ColorSwatch s) {
    return {
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

  Task _taskFromRow(Map<String, Object?> r) {
    return Task(
      id: r['id'] as String,
      title: r['title'] as String,
      plannedStart: r['planned_start'] as int,
      plannedEnd: r['planned_end'] as int,
      actualStart: r['actual_start'] as int?,
      actualEnd: r['actual_end'] as int?,
      isDone: (r['is_done'] as int) != 0,
      primaryTagId: r['primary_tag_id'] as String?,
      autoSwatchId: r['auto_swatch_id'] as String,
      overrideSwatchId: r['override_swatch_id'] as String?,
      notes: r['notes'] as String?,
      createdAt: r['created_at'] as int,
    );
  }

  Map<String, Object?> _rowFromTask(Task t) {
    return {
      'id': t.id,
      'title': t.title,
      'planned_start': t.plannedStart,
      'planned_end': t.plannedEnd,
      'actual_start': t.actualStart,
      'actual_end': t.actualEnd,
      'is_done': t.isDone ? 1 : 0,
      'primary_tag_id': t.primaryTagId,
      'auto_swatch_id': t.autoSwatchId,
      'override_swatch_id': t.overrideSwatchId,
      'notes': t.notes,
      'created_at': t.createdAt,
    };
  }
}
