bool taskMatchesTagFilter({
  required String? tagId,
  required Set<String> filterTagIds,
}) {
  if (filterTagIds.isEmpty) return true;
  return tagId != null && filterTagIds.contains(tagId);
}
