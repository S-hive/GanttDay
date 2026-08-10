import 'dart:async';

import 'package:flutter/material.dart' hide ColorSwatch;
import 'package:sqflite_common/sqlite_api.dart';

import 'domain/gantt/factory_swatches.dart';
import 'domain/models/color_swatch.dart';
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

/// Theme seed from settings default swatch (ARGB). Falls back to factory azure.
Color themeSeedFromSwatches(Iterable<ColorSwatch> swatches) {
  for (final s in swatches) {
    if (s.isDefault) return Color(s.argb);
  }
  if (swatches.isNotEmpty) return Color(swatches.first.argb);
  final factory = kFactoryColorSwatches.firstWhere((s) => s.isDefault);
  return Color(factory.argb);
}

class GanttDayApp extends StatefulWidget {
  const GanttDayApp({super.key, required this.services});

  final AppServices services;

  @override
  State<GanttDayApp> createState() => _GanttDayAppState();
}

class _GanttDayAppState extends State<GanttDayApp> {
  StreamSubscription<List<ColorSwatch>>? _swatchesSub;
  Color _seedColor = themeSeedFromSwatches(kFactoryColorSwatches);

  @override
  void initState() {
    super.initState();
    _swatchesSub = widget.services.tasks.watchSwatches().listen((swatches) {
      final next = themeSeedFromSwatches(swatches);
      if (!mounted || next.toARGB32() == _seedColor.toARGB32()) return;
      setState(() => _seedColor = next);
    });
  }

  @override
  void dispose() {
    _swatchesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Also wrap here (not only in main) so hot reload picks it up; main() is
    // not re-run on hot reload. Avoids Windows AXTree spam on dense Gantt UIs.
    return ExcludeSemantics(
      child: MaterialApp(
        title: 'GanttDay',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          // Seed derives the palette; pin primary to the default swatch ARGB
          // so create frames / nav / buttons match settings exactly.
          colorScheme: ColorScheme.fromSeed(seedColor: _seedColor).copyWith(
            primary: _seedColor,
          ),
          useMaterial3: true,
        ),
        home: AppShell(services: widget.services),
      ),
    );
  }
}
