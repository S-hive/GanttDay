import '../models/tag.dart';
import '../models/task.dart';
import 'factory_swatches.dart';

int resolveTaskArgb(
  Task task,
  Map<String, Tag> tags, {
  int? currentDefaultArgb,
}) {
  final override = task.overrideArgb;
  if (override != null) return override;
  final tagId = task.tagId;
  if (tagId != null) {
    final tag = tags[tagId];
    if (tag != null) return tag.argb;
  }
  return currentDefaultArgb ?? kFallbackArgb;
}
