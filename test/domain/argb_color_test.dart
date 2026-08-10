import 'package:ganttday/domain/gantt/argb_color.dart';
import 'package:test/test.dart';

void main() {
  test('parseHex accepts #RGB and #RRGGBB', () {
    expect(ArgbColor.parseHex('#abc'), 0xFFAABBCC);
    expect(ArgbColor.parseHex('#AABBCC'), 0xFFAABBCC);
    expect(ArgbColor.parseHex('ffdac1'), 0xFFFFDAC1);
    expect(ArgbColor.parseHex('nope'), isNull);
  });

  test('toHex formats #RRGGBB uppercase', () {
    expect(ArgbColor.toHex(0xFFFFDAC1), '#FFDAC1');
  });

  test('toHsl matches known azure approx', () {
    final hsl = ArgbColor.toHsl(0xFF457BD9);
    expect(hsl.hue, closeTo(218, 2));
    expect(hsl.saturation, greaterThan(0.5));
    expect(hsl.lightness, closeTo(0.56, 0.05));
  });
}
