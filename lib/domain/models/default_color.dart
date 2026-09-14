class DefaultColor {
  const DefaultColor({
    required this.id,
    required this.argb,
    required this.sortOrder,
    this.isCurrent = false,
  });

  final String id;
  final int argb;
  final int sortOrder;
  final bool isCurrent;
}
