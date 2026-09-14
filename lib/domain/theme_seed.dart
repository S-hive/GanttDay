import 'gantt/factory_swatches.dart';
import 'models/default_color.dart';

/// ARGB theme seed from the current default color. Falls back to 霁蓝.
int themeSeedFromDefaultColors(Iterable<DefaultColor> colors) {
  for (final c in colors) {
    if (c.isCurrent) return c.argb;
  }
  return kFallbackArgb;
}
