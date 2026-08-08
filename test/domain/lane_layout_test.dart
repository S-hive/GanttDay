import 'package:ganttday/domain/gantt/lane_layout.dart';
import 'package:ganttday/domain/models/gantt_segment.dart';
import 'package:test/test.dart';

void main() {
  test('non-overlapping abutting segments share lane 0', () {
    const a = GanttSegment(taskId: '1', start: 0, end: 60);
    const b = GanttSegment(taskId: '2', start: 60, end: 120);
    final lanes = LaneLayout.assign([a, b]);
    expect(lanes['1:0'], 0);
    expect(lanes['2:60'], 0);
  });

  test('partial overlap uses distinct lanes', () {
    const a = GanttSegment(taskId: '1', start: 0, end: 90);
    const b = GanttSegment(taskId: '2', start: 60, end: 120);
    final lanes = LaneLayout.assign([a, b]);
    expect(lanes['1:0'] != lanes['2:60'], true);
  });

  test('full overlap uses distinct lanes', () {
    const a = GanttSegment(taskId: '1', start: 0, end: 60);
    const b = GanttSegment(taskId: '2', start: 0, end: 60);
    final lanes = LaneLayout.assign([a, b]);
    expect({lanes['1:0'], lanes['2:0']}, {0, 1});
  });

  test('freed lane is reused after earlier segment ends', () {
    const a = GanttSegment(taskId: '1', start: 0, end: 60);
    const b = GanttSegment(taskId: '2', start: 30, end: 90);
    const c = GanttSegment(taskId: '3', start: 60, end: 120);
    final lanes = LaneLayout.assign([a, b, c]);
    expect(lanes['1:0'], 0);
    expect(lanes['2:30'], 1);
    expect(lanes['3:60'], 0);
  });

  test('laneCount reports max lane + 1 and 1 for empty', () {
    const a = GanttSegment(taskId: '1', start: 0, end: 60);
    const b = GanttSegment(taskId: '2', start: 0, end: 60);
    expect(LaneLayout.laneCount(LaneLayout.assign([a, b])), 2);
    expect(LaneLayout.laneCount(const {}), 1);
  });
}
