import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/domain/time/inline_datetime.dart';

void main() {
  test('parses valid fields and snaps minutes', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '8', day: '10', hour: '15', minute: '08',
    );
    expect(r.error, isNull);
    expect(r.value, DateTime(2026, 8, 10, 15, 15)); // 08 → 15 via snap inside tryParse
  });

  test('snapToQuarterHour rounds 7→0 and 8→15', () {
    expect(
      InlineDateTimeParse.snapToQuarterHour(DateTime(2026, 1, 1, 10, 7)).minute,
      0,
    );
    expect(
      InlineDateTimeParse.snapToQuarterHour(DateTime(2026, 1, 1, 10, 8)).minute,
      15,
    );
  });

  test('rejects impossible calendar day', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '2', day: '30', hour: '12', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });

  test('rejects non-numeric', () {
    final r = InlineDateTimeParse.tryParse(
      year: '20xx', month: '1', day: '1', hour: '0', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });

  test('rejects hour 24', () {
    final r = InlineDateTimeParse.tryParse(
      year: '2026', month: '1', day: '1', hour: '24', minute: '0',
    );
    expect(r.value, isNull);
    expect(r.error, '日期无效');
  });
}
