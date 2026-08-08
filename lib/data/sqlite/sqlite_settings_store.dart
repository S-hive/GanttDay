import 'dart:async';

import 'package:sqflite_common/sqlite_api.dart';

import '../../domain/models/app_settings.dart';
import '../../platform/settings_store.dart';

class SqliteSettingsStore implements SettingsStore {
  SqliteSettingsStore(this._db);

  static const _kVisibleStartHour = 'visible_start_hour';
  static const _kVisibleEndHour = 'visible_end_hour';
  static const _kUrgencyWindowDays = 'urgency_window_days';

  final Database _db;
  final _changes = StreamController<void>.broadcast();

  Future<void> dispose() => _changes.close();

  @override
  Stream<AppSettings> watch() {
    late StreamController<AppSettings> controller;
    StreamSubscription<void>? changeSub;

    Future<void> emit() async {
      final settings = await read();
      if (!controller.isClosed) controller.add(settings);
    }

    controller = StreamController<AppSettings>(
      onListen: () {
        emit();
        changeSub = _changes.stream.listen((_) => emit());
      },
      onCancel: () async {
        await changeSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<AppSettings> read() async {
    final rows = await _db.query('setting');
    final map = {
      for (final r in rows) r['key'] as String: r['value'] as String,
    };
    const defaults = AppSettings();
    return AppSettings(
      visibleStartHour: int.tryParse(map[_kVisibleStartHour] ?? '') ??
          defaults.visibleStartHour,
      visibleEndHour:
          int.tryParse(map[_kVisibleEndHour] ?? '') ?? defaults.visibleEndHour,
      urgencyWindowDays: int.tryParse(map[_kUrgencyWindowDays] ?? '') ??
          defaults.urgencyWindowDays,
    );
  }

  @override
  Future<void> write(AppSettings settings) async {
    await _db.transaction((txn) async {
      final entries = {
        _kVisibleStartHour: settings.visibleStartHour,
        _kVisibleEndHour: settings.visibleEndHour,
        _kUrgencyWindowDays: settings.urgencyWindowDays,
      };
      for (final e in entries.entries) {
        await txn.insert(
          'setting',
          {'key': e.key, 'value': '${e.value}'},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    _changes.add(null);
  }
}
