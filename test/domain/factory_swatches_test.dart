import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:test/test.dart';

void main() {
  test('eight factory swatches; azure default', () {
    expect(kFactoryColorSwatches, hasLength(8));
    expect(kDefaultSwatchId, 'azure');
    expect(
      kFactoryColorSwatches.singleWhere((s) => s.isDefault).id,
      'azure',
    );
    expect(
      [for (final s in kFactoryColorSwatches) s.argb],
      [
        0xFF457BD9,
        0xFFFFDAC1,
        0xFFE2F0CB,
        0xFFB5EAD7,
        0xFFDDD6FE,
        0xFFBAE6FD,
        0xFFFEF3C7,
        0xFFDEE2E6,
      ],
    );
    expect(kFactoryColorSwatches.singleWhere((s) => s.id == 'gray').slate, isTrue);
  });
}
