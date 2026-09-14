import 'package:ganttday/domain/gantt/tag_filter.dart';
import 'package:test/test.dart';

void main() {
  test('empty filter matches everything', () {
    expect(
      taskMatchesTagFilter(tagId: null, filterTagIds: const {}),
      isTrue,
    );
    expect(
      taskMatchesTagFilter(tagId: 'a', filterTagIds: const {}),
      isTrue,
    );
  });

  test('matches the single tag', () {
    expect(
      taskMatchesTagFilter(tagId: 'work', filterTagIds: {'work'}),
      isTrue,
    );
  });

  test('rejects a different tag', () {
    expect(
      taskMatchesTagFilter(tagId: 'work', filterTagIds: {'sport'}),
      isFalse,
    );
  });

  test('untagged task is hidden when a filter is on', () {
    expect(
      taskMatchesTagFilter(tagId: null, filterTagIds: {'work'}),
      isFalse,
    );
  });
}
