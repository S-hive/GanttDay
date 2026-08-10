import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

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
