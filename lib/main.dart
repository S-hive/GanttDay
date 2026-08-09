import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'data/sqlite/app_database.dart';
import 'data/sqlite/sqlite_settings_store.dart';
import 'data/sqlite/sqlite_task_repository.dart';
import 'data/windows_file_gateway.dart';
import 'platform/task_repository.dart';
import 'ui/common/db_error_screen.dart';
import 'windows_safe_binding.dart';

Future<void> main() async {
  // Must run before any other binding init. Hot restart does NOT re-run this
  // for a new native AXTree — quit the process (Ctrl+C) after first install.
  WindowsSafeWidgetsBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final supportDir = await getApplicationSupportDirectory();
  await supportDir.create(recursive: true);
  final dbPath = p.join(supportDir.path, 'gantday.db');

  await _openAndRun(dbPath);
}

Future<void> _openAndRun(String dbPath) async {
  try {
    final db = await AppDatabase.open(databaseFactory, dbPath);
    final services = AppServices(
      db: db,
      tasks: SqliteTaskRepository(db),
      settings: SqliteSettingsStore(db),
      files: WindowsFileGateway(),
    );
    runApp(_wrapForPlatform(GanttDayApp(services: services)));
  } on DatabaseOpenException catch (e) {
    runApp(_wrapForPlatform(MaterialApp(
      title: 'GanttDay',
      debugShowCheckedModeBanner: false,
      home: DbErrorScreen(
        message: e.message,
        path: dbPath,
        onBackupAndContinue: () async {
          final stamp = DateTime.now()
              .toIso8601String()
              .replaceAll(':', '-')
              .split('.')
              .first;
          await File(dbPath).rename('$dbPath.corrupt-$stamp');
          await _openAndRun(dbPath);
        },
        onQuit: () => exit(0),
      ),
    )));
  }
}

/// Windows accessibility bridge corrupts easily with dense Gantt UIs (AXTree
/// "will not be in the tree"). Exclude the whole app from semantics there.
Widget _wrapForPlatform(Widget app) {
  if (Platform.isWindows) {
    return ExcludeSemantics(child: app);
  }
  return app;
}
