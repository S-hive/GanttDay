import 'dart:math' as math;

/// Picks a random hue far from existing tag hues, decided once at task
/// creation and stored — never recomputed at paint time (spec section 4).
int pickAutoHue(List<int> existingHues, [math.Random? rng]) {
  final random = rng ?? math.Random();
  if (existingHues.isEmpty) return random.nextInt(360);

  var bestHue = 0;
  var bestDistance = -1;
  for (var i = 0; i < 24; i++) {
    final candidate = random.nextInt(360);
    var minDistance = 360;
    for (final hue in existingHues) {
      final direct = (candidate - hue).abs() % 360;
      final circular = math.min(direct, 360 - direct);
      if (circular < minDistance) minDistance = circular;
    }
    if (minDistance > bestDistance) {
      bestDistance = minDistance;
      bestHue = candidate;
    }
  }
  return bestHue;
}
