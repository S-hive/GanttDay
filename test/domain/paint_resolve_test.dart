import 'package:ganttday/domain/gantt/factory_swatches.dart';
import 'package:ganttday/domain/gantt/paint_resolve.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:test/test.dart';

Task _task({String? tagId, int? overrideArgb}) => Task(
      id: '1',
      title: 'x',
      plannedStart: 0,
      plannedEnd: 1,
      tagId: tagId,
      overrideArgb: overrideArgb,
      createdAt: 0,
    );

void main() {
  const tags = {
    'tg': Tag(id: 'tg', name: '学习', argb: 0xFF7EB6F0, sortOrder: 0),
  };

  test('override wins over tag and default', () {
    expect(
      resolveTaskArgb(
        _task(tagId: 'tg', overrideArgb: 0xFF60A5FA),
        tags,
        currentDefaultArgb: 0xFFFFDAC1,
      ),
      0xFF60A5FA,
    );
  });

  test('tag argb used when no override', () {
    expect(
      resolveTaskArgb(_task(tagId: 'tg'), tags, currentDefaultArgb: 0xFFFFDAC1),
      0xFF7EB6F0,
    );
  });

  test('missing tag falls through to current default', () {
    expect(
      resolveTaskArgb(_task(tagId: 'gone'), tags, currentDefaultArgb: 0xFFFFDAC1),
      0xFFFFDAC1,
    );
  });

  test('no tag uses current default then fallback', () {
    expect(
      resolveTaskArgb(_task(), const {}, currentDefaultArgb: 0xFFFFDAC1),
      0xFFFFDAC1,
    );
    expect(resolveTaskArgb(_task(), const {}), kFallbackArgb);
  });

  test('fallback constant is 霁蓝', () {
    expect(kFallbackArgb, 0xFF457BD9);
  });
}
