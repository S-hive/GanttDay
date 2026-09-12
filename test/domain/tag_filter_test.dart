import 'package:ganttday/domain/gantt/tag_filter.dart';
import 'package:test/test.dart';

void main() {
  test('empty filter matches everything', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: null,
        attachedTagIds: const [],
        filterTagIds: const {},
      ),
      isTrue,
    );
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'a',
        attachedTagIds: const ['b'],
        filterTagIds: const {},
      ),
      isTrue,
    );
  });

  test('matches primary tag', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const [],
        filterTagIds: {'work'},
      ),
      isTrue,
    );
  });

  test('matches attached tag without primary', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: null,
        attachedTagIds: const ['life'],
        filterTagIds: {'life'},
      ),
      isTrue,
    );
  });

  test('matches attached tag when primary differs', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const ['life'],
        filterTagIds: {'life'},
      ),
      isTrue,
    );
  });

  test('rejects when neither primary nor attached hits', () {
    expect(
      taskMatchesTagFilter(
        primaryTagId: 'work',
        attachedTagIds: const ['life'],
        filterTagIds: {'sport'},
      ),
      isFalse,
    );
  });
}
