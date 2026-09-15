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
import 'package:ganttday/ui/shell/app_shell.dart';
import 'package:sqflite_common/sqlite_api.dart';

void main() {
  testWidgets('AppBar has no tag filter icon even when tags exist',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppShell(
          services: AppServices(
            db: _FakeDb(),
            tasks: _StubTasks(),
            settings: _StubSettings(),
            files: _StubFiles(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byTooltip('标签筛选'), findsNothing);
    expect(find.byIcon(Icons.filter_list), findsNothing);
    expect(find.text('全部'), findsNothing);
  });
}

class _FakeDb extends Fake implements Database {}

class _StubSettings implements SettingsStore {
  @override
  Stream<AppSettings> watch() => Stream.value(const AppSettings());

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
      Stream.value(const []);

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
  Future<List<Tag>> listTags() async => const [
        Tag(id: 'work', name: '工作', argb: 0xFF457BD9, sortOrder: 0),
      ];

  @override
  Future<void> upsertTag(Tag tag) async {}

  @override
  Future<void> deleteTag(String id) async {}

  @override
  Future<List<DefaultColor>> listDefaultColors() async => const [];

  @override
  Stream<List<DefaultColor>> watchDefaultColors() => Stream.value(const []);

  @override
  Future<DefaultColor?> currentDefaultColor() async => null;

  @override
  Future<void> upsertDefaultColor(DefaultColor color) async {}

  @override
  Future<void> deleteDefaultColor(String id) async {}
}
