import 'package:flutter/material.dart';

import '../../app.dart';

/// Placeholder shell — the day Gantt view replaces this in the next task.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('GanttDay')),
    );
  }
}
