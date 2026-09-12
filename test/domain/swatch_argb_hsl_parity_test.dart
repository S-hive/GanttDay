import 'package:ganttday/domain/gantt/argb_color.dart';
import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:test/test.dart';

int channelDelta(int a, int b) {
  final ar = (a >> 16) & 0xFF;
  final ag = (a >> 8) & 0xFF;
  final ab = a & 0xFF;
  final br = (b >> 16) & 0xFF;
  final bg = (b >> 8) & 0xFF;
  final bb = b & 0xFF;
  return (ar - br).abs() + (ag - bg).abs() + (ab - bb).abs();
}

/// Tag chips use swatch.argb; bars rebuild via HSL (colorOf). Spec: ARGB wins.
void main() {
  test('factory stored HSL round-trips to same ARGB as tag chip', () {
    final mismatches = <String>[];
    for (final s in kFactoryColorSwatches) {
      final fromHsl = ArgbColor.fromHsl(
        s.hue.toDouble(),
        s.saturation,
        s.lightness,
      );
      final delta = channelDelta(s.argb, fromHsl);
      if (delta > 3) {
        final trueHsl = ArgbColor.toHsl(s.argb);
        mismatches.add(
          '${s.id}: argb=${ArgbColor.toHex(s.argb)} '
          'hslRebuild=${ArgbColor.toHex(fromHsl)} delta=$delta '
          'stored=${s.hue}/${s.saturation}/${s.lightness} '
          'true=${trueHsl.hue.toStringAsFixed(1)}/'
          '${trueHsl.saturation.toStringAsFixed(3)}/'
          '${trueHsl.lightness.toStringAsFixed(3)}',
        );
      }
    }
    expect(mismatches, isEmpty, reason: mismatches.join('\n'));
  });
}
