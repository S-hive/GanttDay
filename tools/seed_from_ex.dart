// ignore_for_file: avoid_print
/// Wipe all tasks and seed from repo-root `ex.json`.
///
/// Usage (close the running app first if the DB is locked):
///   dart run tools/seed_from_ex.dart
///   dart run tools/seed_from_ex.dart --db "C:\path\to\gantday.db"
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Same encoding as `WallClock.minutes` (UTC clock-face minutes).
int wallMinutes(DateTime local) {
  final utc = DateTime.utc(
      local.year, local.month, local.day, local.hour, local.minute);
  return utc.millisecondsSinceEpoch ~/ 60000;
}

Future<void> main(List<String> args) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final exPath = p.join(Directory.current.path, 'ex.json');
  if (!File(exPath).existsSync()) {
    stderr.writeln('Missing $exPath (run from repo root)');
    exit(1);
  }

  String? dbPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--db' && i + 1 < args.length) {
      dbPath = args[i + 1];
    }
  }
  dbPath ??= await _findDb();
  if (dbPath == null || !File(dbPath).existsSync()) {
    stderr.writeln(
        'Could not find gantday.db. Pass --db <path> or start the app once.');
    exit(1);
  }
  print('DB: $dbPath');

  final root = jsonDecode(await File(exPath).readAsString()) as Map;
  final month = root['month'] as String; // 2026-08
  final year = int.parse(month.split('-')[0]);
  final days = root['days'] as List;

  final uuid = const Uuid();
  final tasks = <Map<String, Object?>>[];
  final seenMulti = <String>{};

  for (final dayRaw in days) {
    final day = dayRaw as Map;
    final md = day['date'] as String; // 08-01
    final parts = md.split('-');
    final monthOfDay = int.parse(parts[0]);
    final dayOfMonth = int.parse(parts[1]);
    final baseDate = DateTime(year, monthOfDay, dayOfMonth);

    for (final tRaw in day['tasks'] as List) {
      final t = tRaw as Map;
      final name = t['name'] as String;
      final type = t['type'] as String;
      final plan = (t['plan'] as List).cast<String>();
      final actual = (t['actual'] as List?)?.cast<String>();

      // Multi-day tasks are listed only on the start day; skip if we somehow
      // see a duplicate name+plan key again.
      if (type == 'multi') {
        final key = '$name|${plan[0]}|${plan[1]}';
        if (!seenMulti.add(key)) continue;
      }

      final plannedStart = _parseInstant(plan[0], baseDate, year);
      final plannedEnd = _parseInstant(plan[1], baseDate, year);
      WallMinutes? actualStart;
      WallMinutes? actualEnd;
      var isDone = false;
      if (actual != null && actual.length >= 2) {
        actualStart = _parseInstant(actual[0], baseDate, year);
        actualEnd = _parseInstant(actual[1], baseDate, year);
        isDone = true;
      }

      tasks.add({
        'id': uuid.v4(),
        'title': name,
        'planned_start': plannedStart,
        'planned_end': plannedEnd,
        'actual_start': actualStart,
        'actual_end': actualEnd,
        'is_done': isDone ? 1 : 0,
        'tag_id': null,
        'override_argb': null,
        'notes': type == 'daily'
            ? '日常'
            : (type == 'multi' ? '跨天' : null),
        'created_at': plannedStart,
      });
    }
  }

  print('Parsed ${tasks.length} tasks from ex.json');

  final db = await databaseFactory.openDatabase(dbPath);
  try {
    await db.transaction((txn) async {
      final deleted = await txn.delete('task');
      print('Deleted $deleted existing tasks');
      for (final row in tasks) {
        await txn.insert('task', row);
      }
    });
    print('Inserted ${tasks.length} tasks. Restart / hot-restart the app.');
  } finally {
    await db.close();
  }
}

typedef WallMinutes = int;

WallMinutes _parseInstant(String raw, DateTime baseDate, int year) {
  // "08-03 09:00" or "06:30"
  if (raw.contains(' ')) {
    final bits = raw.split(RegExp(r'\s+'));
    final md = bits[0].split('-');
    final hm = bits[1].split(':');
    return wallMinutes(DateTime(
      year,
      int.parse(md[0]),
      int.parse(md[1]),
      int.parse(hm[0]),
      int.parse(hm[1]),
    ));
  }
  final hm = raw.split(':');
  return wallMinutes(DateTime(
    baseDate.year,
    baseDate.month,
    baseDate.day,
    int.parse(hm[0]),
    int.parse(hm[1]),
  ));
}

Future<String?> _findDb() async {
  final candidates = <String>[];
  final appData = Platform.environment['APPDATA'];
  final local = Platform.environment['LOCALAPPDATA'];
  for (final root in [appData, local]) {
    if (root == null) continue;
    candidates.addAll(await _searchFile(root, 'gantday.db', maxDepth: 6));
  }
  if (candidates.isEmpty) return null;
  // Prefer newest.
  candidates.sort((a, b) =>
      File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync()));
  return candidates.first;
}

Future<List<String>> _searchFile(String root, String name,
    {int maxDepth = 5}) async {
  final found = <String>[];
  Future<void> walk(Directory dir, int depth) async {
    if (depth > maxDepth) return;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is File && p.basename(entity.path) == name) {
          found.add(entity.path);
        } else if (entity is Directory) {
          final base = p.basename(entity.path);
          if (base == 'Temp' || base == 'Packages' || base.startsWith('.')) {
            continue;
          }
          await walk(entity, depth + 1);
        }
      }
    } catch (_) {
      // permission / locked
    }
  }

  await walk(Directory(root), 0);
  // Also check common Flutter path_provider layout quickly.
  final quick = [
    p.join(root, 'com.example', 'ganttday', 'gantday.db'),
    p.join(root, 'ganttday', 'gantday.db'),
  ];
  for (final q in quick) {
    if (File(q).existsSync() && !found.contains(q)) found.add(q);
  }
  return found;
}
