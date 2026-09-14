import '../models/color_swatch.dart';

const String kDefaultSwatchId = 'azure';
const int kFallbackArgb = 0xFF457BD9;

/// Seed rows for new DBs and schema 1→2 migration. H/S/L match prior palette.
const List<ColorSwatch> kFactoryColorSwatches = [
  ColorSwatch(
    id: 'azure',
    name: '霁蓝',
    argb: 0xFF457BD9,
    hue: 218,
    saturation: 0.661,
    lightness: 0.561,
    sortOrder: 0,
    isDefault: true,
  ),
  ColorSwatch(
    id: 'peach',
    name: '桃',
    argb: 0xFFFFDAC1,
    hue: 24,
    saturation: 1.0,
    lightness: 0.878,
    sortOrder: 1,
  ),
  ColorSwatch(
    id: 'leaf',
    name: '芽绿',
    argb: 0xFFE2F0CB,
    hue: 83,
    saturation: 0.551,
    lightness: 0.869,
    sortOrder: 2,
  ),
  ColorSwatch(
    id: 'mint',
    name: '薄荷',
    argb: 0xFFB5EAD7,
    hue: 158,
    saturation: 0.559,
    lightness: 0.814,
    sortOrder: 3,
  ),
  ColorSwatch(
    id: 'lavender',
    name: '淡紫',
    argb: 0xFFDDD6FE,
    hue: 251,
    saturation: 0.951,
    lightness: 0.918,
    sortOrder: 4,
  ),
  ColorSwatch(
    id: 'sky',
    name: '天空',
    argb: 0xFFBAE6FD,
    hue: 201,
    saturation: 0.943,
    lightness: 0.861,
    sortOrder: 5,
  ),
  ColorSwatch(
    id: 'cream',
    name: '奶油',
    argb: 0xFFFEF3C7,
    hue: 48,
    saturation: 0.964,
    lightness: 0.888,
    sortOrder: 6,
  ),
  ColorSwatch(
    id: 'gray',
    name: '灰',
    argb: 0xFFDEE2E6,
    hue: 211,
    saturation: 0.137,
    lightness: 0.886,
    sortOrder: 7,
    slate: true,
  ),
];
