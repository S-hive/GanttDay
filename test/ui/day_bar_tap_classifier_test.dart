import 'package:fake_async/fake_async.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/ui/day/day_bar_tap_classifier.dart';

void main() {
  test('single up then timeout fires onSingleTap once', () {
    fakeAsync((async) {
      final taps = <String>[];
      final doubles = <String>[];
      final c = DayBarTapClassifier(
        onSingleTap: taps.add,
        onDoubleTap: doubles.add,
      );
      c.down('a');
      c.up();
      expect(taps, isEmpty);
      async.elapse(kDoubleTapTimeout);
      expect(taps, ['a']);
      expect(doubles, isEmpty);
      c.dispose();
    });
  });

  test('two ups on same id within timeout fire onDoubleTap immediately', () {
    fakeAsync((async) {
      final taps = <String>[];
      final doubles = <String>[];
      final c = DayBarTapClassifier(
        onSingleTap: taps.add,
        onDoubleTap: doubles.add,
      );
      c.down('a');
      c.up();
      c.down('a');
      c.up();
      expect(doubles, ['a']);
      expect(taps, isEmpty);
      async.elapse(kDoubleTapTimeout);
      expect(taps, isEmpty);
      c.dispose();
    });
  });

  test('second down on a different id is not a double tap', () {
    fakeAsync((async) {
      final taps = <String>[];
      final doubles = <String>[];
      final c = DayBarTapClassifier(
        onSingleTap: taps.add,
        onDoubleTap: doubles.add,
      );
      c.down('a');
      c.up();
      c.down('b');
      c.up();
      expect(doubles, isEmpty);
      async.elapse(kDoubleTapTimeout);
      expect(taps, ['b']);
      c.dispose();
    });
  });

  test('movedBeyondSlop cancels pending tap and double-tap', () {
    fakeAsync((async) {
      final taps = <String>[];
      final doubles = <String>[];
      final c = DayBarTapClassifier(
        onSingleTap: taps.add,
        onDoubleTap: doubles.add,
      );
      c.down('a');
      c.movedBeyondSlop();
      c.up();
      async.elapse(kDoubleTapTimeout);
      expect(taps, isEmpty);
      expect(doubles, isEmpty);
      c.dispose();
    });
  });

  test('up while still waiting for first up does not open on down', () {
    fakeAsync((async) {
      final doubles = <String>[];
      final c = DayBarTapClassifier(
        onSingleTap: (_) {},
        onDoubleTap: doubles.add,
      );
      c.down('a');
      expect(doubles, isEmpty);
      c.dispose();
    });
  });
}
