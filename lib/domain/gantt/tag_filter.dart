bool taskMatchesTagFilter({
  required String? primaryTagId,
  required List<String> attachedTagIds,
  required Set<String> filterTagIds,
}) {
  if (filterTagIds.isEmpty) return true;
  if (primaryTagId != null && filterTagIds.contains(primaryTagId)) {
    return true;
  }
  return attachedTagIds.any(filterTagIds.contains);
}
