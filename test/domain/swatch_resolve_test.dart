import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/gantt/swatch_resolve.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:test/test.dart';

void main() {
  test('resolve prefers override then tag then auto', () {
    final tags = {
      'tg': const Tag(id: 'tg', name: 't', swatchId: 'peach'),
    };
    final task = Task(
      id: '1',
      title: 'x',
      plannedStart: 0,
      plannedEnd: 1,
      autoSwatchId: 'azure',
      primaryTagId: 'tg',
      overrideSwatchId: 'mint',
      createdAt: 0,
    );
    expect(resolveTaskSwatchId(task, tags), 'mint');
    expect(
      resolveTaskSwatchId(
        task.copyWith(clearOverrideSwatch: true),
        tags,
      ),
      'peach',
    );
    expect(
      resolveTaskSwatchId(
        task.copyWith(clearOverrideSwatch: true, clearPrimaryTag: true),
        tags,
      ),
      'azure',
    );
  });

  test('farthestSwatchId picks swatch maximally distant from existing hues', () {
    expect(
      farthestSwatchId(kFactoryColorSwatches, const []),
      kDefaultSwatchId,
    );
    // peach hue 24 — sky (201) is farthest in factory palette
    final id = farthestSwatchId(kFactoryColorSwatches, const [24]);
    expect(id, 'sky');
  });

  test('farthestSwatchId throws when palette empty', () {
    expect(
      () => farthestSwatchId(const [], const [24]),
      throwsA(isA<StateError>()),
    );
  });

  test('colorSwatchFromArgb derives hsl from argb', () {
    final swatch = colorSwatchFromArgb(
      id: 'x',
      name: 'X',
      argb: 0xFF457BD9,
      sortOrder: 0,
      isDefault: true,
    );
    expect(swatch.hue, 218);
    expect(swatch.saturation, closeTo(0.661, 0.01));
    expect(swatch.lightness, closeTo(0.561, 0.01));
  });
}
