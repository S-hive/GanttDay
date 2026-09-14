import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/default_color.dart';
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
    await _db.delete('task', where: 'id = ?', whereArgs: [id]);
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
    final rows = await _db.query('tag', orderBy: 'sort_order ASC');
    return rows.map(_tagFromRow).toList();
  }

  @override
  Future<void> upsertTag(Tag tag) async {
    if (tag.name.trim().isEmpty) {
      throw TagOperationException('Tag name cannot be empty');
    }
    final collision = await _db.query(
      'tag',
      columns: ['id'],
      where: 'name = ? AND id != ?',
      whereArgs: [tag.name, tag.id],
      limit: 1,
    );
    if (collision.isNotEmpty) {
      throw TagOperationException('Tag name already exists');
    }
    await _db.insert(
      'tag',
      {
        'id': tag.id,
        'name': tag.name,
        'argb': tag.argb,
        'sort_order': tag.sortOrder,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    _notify();
  }

  @override
  Future<void> deleteTag(String id) async {
    await _db.transaction((txn) async {
      await txn.update(
        'task',
        {'tag_id': null},
        where: 'tag_id = ?',
        whereArgs: [id],
      );
      await txn.delete('tag', where: 'id = ?', whereArgs: [id]);
    });
    _notify();
  }

  @override
  Future<List<DefaultColor>> listDefaultColors() async {
    final rows = await _db.query('default_color', orderBy: 'sort_order ASC');
    return rows.map(_defaultColorFromRow).toList();
  }

  @override
  Stream<List<DefaultColor>> watchDefaultColors() {
    late StreamController<List<DefaultColor>> controller;
    StreamSubscription<void>? changeSub;

    Future<void> emit() async {
      final result = await listDefaultColors();
      if (!controller.isClosed) controller.add(result);
    }

    controller = StreamController<List<DefaultColor>>(
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
  Future<DefaultColor?> currentDefaultColor() async {
    final rows = await _db.query(
      'default_color',
      where: 'is_current = 1',
      limit: 1,
    );
    return rows.isEmpty ? null : _defaultColorFromRow(rows.first);
  }

  @override
  Future<void> upsertDefaultColor(DefaultColor color) async {
    final existing = await _db.query(
      'default_color',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [color.id],
      limit: 1,
    );
    final isNew = existing.isEmpty;
    final makeCurrent = color.isCurrent || isNew;
    await _db.transaction((txn) async {
      if (makeCurrent) {
        await txn.update('default_color', {'is_current': 0});
      }
      await txn.insert(
        'default_color',
        {
          'id': color.id,
          'argb': color.argb,
          'is_current': makeCurrent ? 1 : 0,
          'sort_order': color.sortOrder,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
    _notify();
  }

  @override
  Future<void> deleteDefaultColor(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('default_color', where: 'id = ?', whereArgs: [id]);
      final current = await txn.query(
        'default_color',
        columns: ['id'],
        where: 'is_current = 1',
        limit: 1,
      );
      if (current.isEmpty) {
        await txn.rawUpdate(
          'UPDATE default_color SET is_current = 1 WHERE id = '
          '(SELECT id FROM default_color ORDER BY sort_order LIMIT 1)',
        );
      }
    });
    _notify();
  }

  Tag _tagFromRow(Map<String, Object?> r) {
    return Tag(
      id: r['id'] as String,
      name: r['name'] as String,
      argb: r['argb'] as int,
      sortOrder: r['sort_order'] as int,
    );
  }

  DefaultColor _defaultColorFromRow(Map<String, Object?> r) {
    return DefaultColor(
      id: r['id'] as String,
      argb: r['argb'] as int,
      sortOrder: r['sort_order'] as int,
      isCurrent: (r['is_current'] as int) != 0,
    );
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
      tagId: r['tag_id'] as String?,
      overrideArgb: r['override_argb'] as int?,
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
      'tag_id': t.tagId,
      'override_argb': t.overrideArgb,
      'notes': t.notes,
      'created_at': t.createdAt,
    };
  }
}
