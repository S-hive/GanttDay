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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
    runApp(GanttDayApp(services: services));
  } on DatabaseOpenException catch (e) {
    runApp(MaterialApp(
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
    ));
  }
}
