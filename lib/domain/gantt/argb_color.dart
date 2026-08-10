import 'dart:math' as math;

class ArgbHsl {
  const ArgbHsl({
    required this.hue,
    required this.saturation,
    required this.lightness,
  });
  final double hue; // 0..360
  final double saturation; // 0..1
  final double lightness; // 0..1
}

class ArgbColor {
  ArgbColor._();

  static int? parseHex(String raw) {
    var s = raw.trim();
    if (s.startsWith('#')) s = s.substring(1);
    if (s.length == 3) {
      s = '${s[0]}${s[0]}${s[1]}${s[1]}${s[2]}${s[2]}';
    }
    if (s.length != 6) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return 0xFF000000 | v;
  }

  static String toHex(int argb) {
    final rgb = argb & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// Standard HSL from sRGB (same convention as Flutter HSLColor).
  static ArgbHsl toHsl(int argb) {
    final r = ((argb >> 16) & 0xFF) / 255.0;
    final g = ((argb >> 8) & 0xFF) / 255.0;
    final b = (argb & 0xFF) / 255.0;
    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final l = (max + min) / 2;
    if (max == min) {
      return ArgbHsl(hue: 0, saturation: 0, lightness: l);
    }
    final d = max - min;
    final s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    double h;
    if (max == r) {
      h = ((g - b) / d + (g < b ? 6 : 0)) / 6;
    } else if (max == g) {
      h = ((b - r) / d + 2) / 6;
    } else {
      h = ((r - g) / d + 4) / 6;
    }
    return ArgbHsl(hue: h * 360, saturation: s, lightness: l);
  }

  /// Standard HSL → opaque ARGB (same convention as Flutter HSLColor).
  static int fromHsl(double hue, double saturation, double lightness) {
    final h = hue % 360;
    final s = saturation.clamp(0.0, 1.0);
    final l = lightness.clamp(0.0, 1.0);
    if (s == 0) {
      final v = (l * 255).round();
      return 0xFF000000 | (v << 16) | (v << 8) | v;
    }
    final q = l < 0.5 ? l * (1 + s) : l + s - l * s;
    final p = 2 * l - q;
    double hue2rgb(double t) {
      if (t < 0) t += 1;
      if (t > 1) t -= 1;
      if (t < 1 / 6) return p + (q - p) * 6 * t;
      if (t < 1 / 2) return q;
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6;
      return p;
    }
    final r = (hue2rgb(h / 360 + 1 / 3) * 255).round();
    final g = (hue2rgb(h / 360) * 255).round();
    final b = (hue2rgb(h / 360 - 1 / 3) * 255).round();
    return 0xFF000000 | (r << 16) | (g << 8) | b;
  }
}
