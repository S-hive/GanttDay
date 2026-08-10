import 'package:test/test.dart';

/// Mirrors the day/week/month watch-load epoch guard: a slower older
/// snapshot must not overwrite a newer one.
void main() {
  test('stale async snapshot is discarded by epoch', () async {
    var epoch = 0;
    String? applied;

    Future<void> apply(String label, int delayMs) async {
      final my = ++epoch;
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      if (my != epoch) return;
      applied = label;
    }

    // Older load is slow; newer load finishes first.
    final older = apply('old', 50);
    final newer = apply('new', 1);
    await Future.wait([older, newer]);

    expect(applied, 'new');
  });
}
