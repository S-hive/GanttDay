import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ganttday/app.dart';
import 'package:ganttday/domain/models/app_settings.dart';
import 'package:ganttday/domain/models/default_color.dart';
import 'package:ganttday/domain/models/tag.dart';
import 'package:ganttday/domain/models/task.dart';
import 'package:ganttday/domain/time/wall_clock.dart';
import 'package:ganttday/platform/file_gateway.dart';
import 'package:ganttday/platform/settings_store.dart';
import 'package:ganttday/platform/task_repository.dart';
import 'package:ganttday/ui/common/rect_swatch.dart';
import 'package:ganttday/ui/settings/settings_page.dart';
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  testWidgets('settings lists show 标签 and 默认色, not 色卡', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              TagSettingsList(
                tags: const [
                  Tag(id: 't1', name: '学习', argb: 0xFF457BD9, sortOrder: 0),
                ],
                onRecolor: (_, __) async {},
                onRename: (_, __) async {},
                onDelete: (_) async {},
                onCreate: (_, __) async {},
              ),
              DefaultColorSettingsList(
                colors: const [
                  DefaultColor(
                    id: 'd1',
                    argb: 0xFFFFDAC1,
                    sortOrder: 0,
                    isCurrent: true,
                  ),
                ],
                onRecolor: (_, __) async {},
                onDelete: (_) async {},
                onCreate: (_) async {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('标签'), findsOneWidget);
    expect(find.text('默认色'), findsOneWidget);
    expect(find.text('色卡'), findsNothing);
  });

  testWidgets('settings page hides 可视时段 and 紧迫窗口', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsPage(
            services: AppServices(
              db: _FakeDb(),
              tasks: _StubTasks(),
              settings: _StubSettings(),
              files: _StubFiles(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('标签'), findsOneWidget);
    expect(find.text('默认色'), findsOneWidget);
    expect(find.text('可视时段'), findsNothing);
    expect(find.text('开始小时'), findsNothing);
    expect(find.text('结束小时'), findsNothing);
    expect(find.textContaining('紧迫窗口'), findsNothing);
  });

  testWidgets('tag row shows rect then name; tap name shows TextField',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagSettingsList(
            tags: const [
              Tag(id: 't1', name: '学习', argb: 0xFF457BD9, sortOrder: 0),
            ],
            onRecolor: (_, __) async {},
            onRename: (_, __) async {},
            onDelete: (_) async {},
            onCreate: (_, __) async {},
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byType(RectSwatch)).dx,
        lessThan(tester.getTopLeft(find.text('学习')).dx));
    expect(find.text('学习'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('zero tags has no disabled delete affordance', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TagSettingsList(
            tags: const [],
            onRecolor: (_, __) async {},
            onRename: (_, __) async {},
            onDelete: (_) async {},
            onCreate: (_, __) async {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text('标签'), findsOneWidget);
  });

  testWidgets('default color row has no name text', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DefaultColorSettingsList(
            colors: const [
              DefaultColor(
                id: 'd1',
                argb: 0xFFFFDAC1,
                sortOrder: 0,
                isCurrent: true,
              ),
            ],
            onRecolor: (_, __) async {},
            onDelete: (_) async {},
            onCreate: (_) async {},
          ),
        ),
      ),
    );

    expect(find.byType(RectSwatch), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('霁蓝'), findsNothing);
    expect(find.text('桃'), findsNothing);
  });
}

class _FakeDb extends Fake implements Database {}

class _StubSettings implements SettingsStore {
  @override
  Stream<AppSettings> watch() => const Stream.empty();

  @override
  Future<AppSettings> read() async => const AppSettings();

  @override
  Future<void> write(AppSettings settings) async {}
}

class _StubFiles implements FileGateway {
  @override
  Future<String?> pickOpenPath({List<String> extensions = const []}) async =>
      null;

  @override
  Future<String?> pickSavePath({
    required String suggestedName,
    List<String> extensions = const [],
  }) async =>
      null;

  @override
  Future<String> readText(String path) async => '';

  @override
  Future<void> writeText(String path, String contents) async {}
}

class _StubTasks implements TaskRepository {
  @override
  Stream<List<Task>> watchTasksOverlapping(
          WallMinutes rangeStart, WallMinutes rangeEnd) =>
      const Stream.empty();

  @override
  Future<Task?> getById(String id) async => null;

  @override
  Future<void> upsert(Task task) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> complete(String id,
      {required WallMinutes actualStart,
      required WallMinutes actualEnd}) async {}

  @override
  Future<void> uncomplete(String id) async {}

  @override
  Future<List<Tag>> listTags() async => const [];

  @override
  Future<void> upsertTag(Tag tag) async {}

  @override
  Future<void> deleteTag(String id) async {}

  @override
  Future<List<DefaultColor>> listDefaultColors() async => const [];

  @override
  Stream<List<DefaultColor>> watchDefaultColors() => const Stream.empty();

  @override
  Future<DefaultColor?> currentDefaultColor() async => null;

  @override
  Future<void> upsertDefaultColor(DefaultColor color) async {}

  @override
  Future<void> deleteDefaultColor(String id) async {}
}
