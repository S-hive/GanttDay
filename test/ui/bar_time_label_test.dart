import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/ui/day/bar_time_label.dart';
import 'package:test/test.dart';

void main() {
  test('formats start end and duration', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 9, 0));
    final end = WallClock.minutes(DateTime(2026, 8, 8, 10, 30));
    expect(formatBarTimeLabel(start, end), '09:00 – 10:30（1h 30m）');
    expect(
      formatBarInlineCaption('拍摄', start, end),
      '拍摄  09:00 – 10:30（1h 30m）',
    );
    expect(
      formatBarHoverDetail(
        title: '面试',
        start: start,
        end: end,
        focusDay: DateTime(2026, 8, 4),
      ),
      '面试\n8月 4日 (星期二) · 09:00 – 10:30（1h 30m）',
    );
  });

  test('overnight span labels end as 次日 and reports multi-day', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 22, 0));
    final end = WallClock.minutes(DateTime(2026, 8, 9, 4, 30));
    expect(spansMultipleCalendarDays(start, end), isTrue);
    expect(formatBarTimeLabel(start, end), '22:00 – 次日 04:30（6h 30m）');
  });

  test('ending exactly at midnight is not multi-day', () {
    final start = WallClock.minutes(DateTime(2026, 8, 8, 22, 0));
    final end = WallClock.minutes(DateTime(2026, 8, 9, 0, 0));
    expect(spansMultipleCalendarDays(start, end), isFalse);
    expect(formatBarTimeLabel(start, end), '22:00 – 00:00（2h）');
  });

  test('preview meta defaults above, flips below when top is clipped', () {
    expect(
      previewMetaLabelAbove(
        barTop: 56,
        barBottom: 76,
        labelExtent: 16,
        clipTop: 32,
        clipBottom: 400,
      ),
      isTrue,
    );
    expect(
      previewMetaLabelAbove(
        barTop: 36,
        barBottom: 56,
        labelExtent: 16,
        clipTop: 32,
        clipBottom: 400,
      ),
      isFalse,
    );
    expect(
      previewMetaLabelAbove(
        barTop: 380,
        barBottom: 400,
        labelExtent: 16,
        clipTop: 32,
        clipBottom: 400,
      ),
      isTrue,
    );
  });

  test('duration helpers', () {
    expect(formatDurationMinutes(15), '15m');
    expect(formatDurationMinutes(60), '1h');
    expect(formatDurationMinutes(90), '1h 30m');
  });

  test('day caption always shows full title + meta without clipping', () {
    for (final mode in [
      resolveBarCaptionMode(canStack: true, overflowCaption: false),
      resolveBarCaptionMode(canStack: false, overflowCaption: false),
      resolveBarCaptionMode(canStack: false, overflowCaption: true),
    ]) {
      expect(mode.showTitle, isTrue);
      expect(mode.showMeta, isTrue);
      expect(mode.clipToBar, isFalse);
    }
  });

  test('sticky caption sticks to viewport when bar left is scrolled away', () {
    // Bar [0, 500], viewport at 200, caption 100 wide → stick at 207.
    expect(
      stickyCaptionLeft(
        barLeft: 0,
        barRight: 500,
        viewportLeft: 200,
        captionWidth: 100,
      ),
      207,
    );
    // Bar left still visible → stay at bar left + padding.
    expect(
      stickyCaptionLeft(
        barLeft: 100,
        barRight: 500,
        viewportLeft: 0,
        captionWidth: 100,
      ),
      107,
    );
    // Near bar end: pin so caption leaves with the bar.
    expect(
      stickyCaptionLeft(
        barLeft: 0,
        barRight: 300,
        viewportLeft: 250,
        captionWidth: 100,
      ),
      193, // 300 - 7 - 100
    );
  });
}
