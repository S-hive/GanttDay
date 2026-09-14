import '../domain/models/default_color.dart';
import '../domain/models/tag.dart';
import '../domain/models/task.dart';
import '../domain/time/wall_clock.dart';

/// Thrown when the database file cannot be opened (corrupt / locked). The UI
/// must surface it — never silently recreate an empty database.
class DatabaseOpenException implements Exception {
  DatabaseOpenException(this.message, {this.path});

  final String message;
  final String? path;

  @override
  String toString() =>
      'DatabaseOpenException: $message${path == null ? '' : ' ($path)'}';
}

/// Thrown when a tag name is empty or collides with an existing tag.
class TagOperationException implements Exception {
  TagOperationException(this.message);

  final String message;

  @override
  String toString() => 'TagOperationException: $message';
}

abstract class TaskRepository {
  /// Tasks whose planned span overlaps [rangeStart, rangeEnd) — this is how
  /// midnight-spanning tasks are found on both days.
  Stream<List<Task>> watchTasksOverlapping(
      WallMinutes rangeStart, WallMinutes rangeEnd);

  Future<Task?> getById(String id);

  Future<void> upsert(Task task);

  Future<void> delete(String id);

  Future<void> complete(String id,
      {required WallMinutes actualStart, required WallMinutes actualEnd});

  /// Reverts to not-done and clears both actual times (no stale data).
  Future<void> uncomplete(String id);

  Future<List<Tag>> listTags();

  Future<void> upsertTag(Tag tag);

  Future<void> deleteTag(String id);

  Future<List<DefaultColor>> listDefaultColors();

  Stream<List<DefaultColor>> watchDefaultColors();

  Future<DefaultColor?> currentDefaultColor();

  Future<void> upsertDefaultColor(DefaultColor color);

  Future<void> deleteDefaultColor(String id);
}
