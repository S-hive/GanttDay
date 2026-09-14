import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/models/default_color.dart';
import 'package:ganttday/domain/theme_seed.dart';
import 'package:test/test.dart';

void main() {
  test('theme seed uses isCurrent argb', () {
    expect(
      themeSeedFromDefaultColors([
        const DefaultColor(id: 'a', argb: 0xFF112233, sortOrder: 0),
        const DefaultColor(
            id: 'b', argb: 0xFFAABBCC, sortOrder: 1, isCurrent: true),
      ]),
      0xFFAABBCC,
    );
  });

  test('empty default colors use fallback', () {
    expect(themeSeedFromDefaultColors(const []), kFallbackArgb);
  });
}
