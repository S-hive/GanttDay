import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:ganttday/app.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/models/color_swatch.dart';
import 'package:test/test.dart';

void main() {
  test('theme seed uses isDefault swatch argb', () {
    final seed = themeSeedFromSwatches([
      const ColorSwatch(
        id: 'a',
        name: 'A',
        argb: 0xFF112233,
        hue: 0,
        saturation: 0.5,
        lightness: 0.5,
        sortOrder: 0,
      ),
      const ColorSwatch(
        id: 'b',
        name: 'B',
        argb: 0xFFAABBCC,
        hue: 0,
        saturation: 0.5,
        lightness: 0.5,
        sortOrder: 1,
        isDefault: true,
      ),
    ]);
    expect(seed.toARGB32(), 0xFFAABBCC);
  });

  test('theme seed falls back to factory default when empty', () {
    final factory = kFactoryColorSwatches.firstWhere((s) => s.isDefault);
    final seed = themeSeedFromSwatches(const []);
    expect(seed.toARGB32(), factory.argb);
  });
}
