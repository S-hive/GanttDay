class ColorSwatch {
  const ColorSwatch({
    required this.id,
    required this.name,
    required this.argb,
    required this.hue,
    required this.saturation,
    required this.lightness,
    required this.sortOrder,
    this.isDefault = false,
    this.slate = false,
  });

  final String id;
  final String name;
  final int argb;
  final int hue;
  final double saturation;
  final double lightness;
  final int sortOrder;
  final bool isDefault;
  final bool slate;

  ColorSwatch copyWith({
    String? name,
    int? argb,
    int? hue,
    double? saturation,
    double? lightness,
    int? sortOrder,
    bool? isDefault,
    bool? slate,
  }) {
    return ColorSwatch(
      id: id,
      name: name ?? this.name,
      argb: argb ?? this.argb,
      hue: hue ?? this.hue,
      saturation: saturation ?? this.saturation,
      lightness: lightness ?? this.lightness,
      sortOrder: sortOrder ?? this.sortOrder,
      isDefault: isDefault ?? this.isDefault,
      slate: slate ?? this.slate,
    );
  }
}
