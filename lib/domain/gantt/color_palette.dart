/// Curated base colors for tags / autoHue / override.
/// [hue]/[saturation]/[lightness] match each hex so urgency can deepen from them.
class PaletteSwatch {
  const PaletteSwatch({
    required this.id,
    required this.name,
    required this.hue,
    required this.saturation,
    required this.lightness,
    required this.argb,
    this.slate = false,
  });

  final String id;
  final String name;
  final int hue;
  final double saturation;
  final double lightness;

  /// Opaque ARGB matching the design hex (e.g. 0xFFFFDAC1).
  final int argb;
  final bool slate;
}

/// Soft pastel bases (user-specified). Gray is the neutral slate swatch.
/// [kDefaultTaskHue] (`#457BD9`) is the default for newly created task bars.
const List<PaletteSwatch> kTaskColorPalette = [
  PaletteSwatch(
    id: 'azure',
    name: '霁蓝',
    hue: 218,
    saturation: 0.661,
    lightness: 0.561,
    argb: 0xFF457BD9,
  ),
  PaletteSwatch(
    id: 'peach',
    name: '桃',
    hue: 24,
    saturation: 1.0,
    lightness: 0.878,
    argb: 0xFFFFDAC1,
  ),
  PaletteSwatch(
    id: 'leaf',
    name: '芽绿',
    hue: 83,
    saturation: 0.551,
    lightness: 0.869,
    argb: 0xFFE2F0CB,
  ),
  PaletteSwatch(
    id: 'mint',
    name: '薄荷',
    hue: 158,
    saturation: 0.559,
    lightness: 0.814,
    argb: 0xFFB5EAD7,
  ),
  PaletteSwatch(
    id: 'lavender',
    name: '淡紫',
    hue: 251,
    saturation: 0.951,
    lightness: 0.918,
    argb: 0xFFDDD6FE,
  ),
  PaletteSwatch(
    id: 'sky',
    name: '天空',
    hue: 201,
    saturation: 0.943,
    lightness: 0.861,
    argb: 0xFFBAE6FD,
  ),
  PaletteSwatch(
    id: 'cream',
    name: '奶油',
    hue: 48,
    saturation: 0.964,
    lightness: 0.888,
    argb: 0xFFFEF3C7,
  ),
  PaletteSwatch(
    id: 'gray',
    name: '灰',
    hue: 211,
    saturation: 0.137,
    lightness: 0.886,
    argb: 0xFFDEE2E6,
    slate: true,
  ),
];

/// Default bar / autoHue color: `#457BD9` (palette id `azure`).
const int kDefaultTaskHue = 218;

/// Fallback preview S/L for custom (non-palette) hues in UI.
const double kPalettePreviewSaturation = 0.55;
const double kPalettePreviewLightness = 0.55;

int circularHueDistance(int a, int b) {
  final direct = (a - b).abs() % 360;
  return direct > 180 ? 360 - direct : direct;
}

/// Index in [kTaskColorPalette] if [hue] matches a swatch exactly.
int? paletteIndexForHue(int hue) {
  for (var i = 0; i < kTaskColorPalette.length; i++) {
    if (kTaskColorPalette[i].hue == hue) return i;
  }
  return null;
}

PaletteSwatch? swatchForHue(int hue) {
  final i = paletteIndexForHue(hue);
  return i == null ? null : kTaskColorPalette[i];
}

/// Farthest palette hue from [existingHues] (ties → earlier swatch).
int farthestPaletteHue(List<int> existingHues) {
  if (existingHues.isEmpty) return kTaskColorPalette.first.hue;
  var bestHue = kTaskColorPalette.first.hue;
  var bestScore = -1;
  for (final swatch in kTaskColorPalette) {
    var minDist = 360;
    for (final h in existingHues) {
      final d = circularHueDistance(swatch.hue, h);
      if (d < minDist) minDist = d;
    }
    if (minDist > bestScore) {
      bestScore = minDist;
      bestHue = swatch.hue;
    }
  }
  return bestHue;
}
