import 'package:ganttday/ui/day/day_gantt_page.dart';
import 'package:test/test.dart';

void main() {
  test('prefers actual below planned when viewport has room', () {
    final lanes = actualEditLanePair(
      preferredPlannedLane: 2,
      viewportLanes: 8,
      hasActual: true,
    );
    expect(lanes.planned, 2);
    expect(lanes.actual, 3);
  });

  test('places actual above when no room below', () {
    final lanes = actualEditLanePair(
      preferredPlannedLane: 7,
      viewportLanes: 8,
      hasActual: true,
    );
    expect(lanes.planned, 7);
    expect(lanes.actual, 6);
  });

  test('swaps when planned is top row and no room below', () {
    final lanes = actualEditLanePair(
      preferredPlannedLane: 0,
      viewportLanes: 1,
      hasActual: true,
    );
    expect(lanes.actual, 0);
    expect(lanes.planned, 1);
  });
}
