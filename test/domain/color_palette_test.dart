import 'dart:math' as math;

import 'package:ganttday/domain/gantt/auto_hue.dart';
import 'package:ganttday/domain/gantt/color_palette.dart';
import 'package:test/test.dart';

void main() {
  test('pickAutoHue defaults to #457BD9 azure', () {
    expect(pickAutoHue([]), kDefaultTaskHue);
    expect(pickAutoHue([24, 83], math.Random(0)), kDefaultTaskHue);
    expect(swatchForHue(kDefaultTaskHue)?.argb, 0xFF457BD9);
  });

  test('farthestPaletteHue prefers distant swatch for tag defaults', () {
    final hue = farthestPaletteHue([24, 83]);
    expect(kTaskColorPalette.map((s) => s.hue), contains(hue));
    expect(hue, isNot(24));
    expect(hue, isNot(83));
  });

  test('paletteIndexForHue matches exact swatches only', () {
    expect(paletteIndexForHue(kDefaultTaskHue), 0);
    expect(paletteIndexForHue(24), 1);
    expect(paletteIndexForHue(200), isNull);
  });

  test('palette includes the specified hex colors', () {
    expect(
      [for (final s in kTaskColorPalette) s.argb],
      [
        0xFF457BD9,
        0xFFFFDAC1,
        0xFFE2F0CB,
        0xFFB5EAD7,
        0xFFDDD6FE,
        0xFFBAE6FD,
        0xFFFEF3C7,
        0xFFDEE2E6,
      ],
    );
  });
}
