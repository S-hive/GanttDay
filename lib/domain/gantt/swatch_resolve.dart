import '../models/color_swatch.dart';
import '../models/tag.dart';
import '../models/task.dart';
import 'argb_color.dart';
import 'factory_swatches.dart';

/// Maps a legacy palette hue to a factory swatch id (unknown → default).
String swatchIdForHue(int hue) {
  for (final s in kFactoryColorSwatches) {
    if (s.hue == hue) return s.id;
  }
  return kDefaultSwatchId;
}

ColorSwatch colorSwatchFromArgb({
  required String id,
  required String name,
  required int argb,
  required int sortOrder,
  bool isDefault = false,
  bool slate = false,
}) {
  final hsl = ArgbColor.toHsl(argb);
  return ColorSwatch(
    id: id,
    name: name,
    argb: argb,
    hue: hsl.hue.round() % 360,
    saturation: hsl.saturation,
    lightness: hsl.lightness,
    sortOrder: sortOrder,
    isDefault: isDefault,
    slate: slate,
  );
}

String resolveTaskSwatchId(Task task, Map<String, Tag> tagsById) {
  final override = task.overrideSwatchId;
  if (override != null) return override;
  final tagId = task.primaryTagId;
  if (tagId != null) {
    final tag = tagsById[tagId];
    if (tag != null) return tag.swatchId;
  }
  return task.autoSwatchId;
}

String farthestSwatchId(
  List<ColorSwatch> palette,
  List<int> existingHues,
) {
  if (palette.isEmpty) {
    throw StateError('palette empty');
  }
  if (existingHues.isEmpty) {
    return palette
        .firstWhere((s) => s.isDefault, orElse: () => palette.first)
        .id;
  }
  var bestId = palette.first.id;
  var bestScore = -1;
  for (final swatch in palette) {
    var minDist = 360;
    for (final h in existingHues) {
      final direct = (swatch.hue - h).abs() % 360;
      final d = direct > 180 ? 360 - direct : direct;
      if (d < minDist) minDist = d;
    }
    if (minDist > bestScore) {
      bestScore = minDist;
      bestId = swatch.id;
    }
  }
  return bestId;
}
