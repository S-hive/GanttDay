import '../domain/models/color_swatch.dart';
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

/// Thrown when a swatch delete or rebind precondition fails.
class SwatchOperationException implements Exception {
  SwatchOperationException(this.message);

  final String message;

  @override
  String toString() => 'SwatchOperationException: $message';
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

  Future<void> setTaskTags(String taskId, List<String> tagIds);

  Future<List<String>> tagIdsForTask(String taskId);

  Future<List<ColorSwatch>> listSwatches();

  /// Re-emits when swatches or task/tag swatch refs change (same bus as tasks).
  Stream<List<ColorSwatch>> watchSwatches();

  Future<ColorSwatch> defaultSwatch();

  Future<void> upsertSwatch(ColorSwatch swatch);

  Future<void> setDefaultSwatch(String id);

  /// Rebinds task auto/override and tag swatch refs from [id] → [rebindToId], then deletes.
  Future<void> deleteSwatch(String id, {required String rebindToId});
}
