import 'dart:math' as math;

import 'color_palette.dart';

/// Returns the default curated palette hue once at task creation and stores it —
/// never recomputed at paint time. Urgency then deepens that base hue.
///
/// Always [kDefaultTaskHue] (`#457BD9`). [existingHues] / [rng] are unused
/// (kept for call-site compatibility).
int pickAutoHue(List<int> existingHues, [math.Random? rng]) {
  return kDefaultTaskHue;
}
