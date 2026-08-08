import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import 'platform/file_gateway.dart';
import 'platform/settings_store.dart';
import 'platform/task_repository.dart';
import 'ui/shell/app_shell.dart';

/// The three platform implementations plus the open database, wired once at
/// startup and handed down to the UI.
class AppServices {
  AppServices({
    required this.db,
    required this.tasks,
    required this.settings,
    required this.files,
  });

  final Database db;
  final TaskRepository tasks;
  final SettingsStore settings;
  final FileGateway files;
}

class GanttDayApp extends StatelessWidget {
  const GanttDayApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GanttDay',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6CF7)),
        useMaterial3: true,
      ),
      home: AppShell(services: services),
    );
  }
}
