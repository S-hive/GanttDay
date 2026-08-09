import 'package:ganttday/data/sqlite/app_database.dart';
import 'package:ganttday/data/sqlite/sqlite_settings_store.dart';
import 'package:ganttday/domain/models/app_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Database db;
  late SqliteSettingsStore store;

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);
    await AppDatabase.applySchema(db);
    store = SqliteSettingsStore(db);
  });

  tearDown(() async {
    await store.dispose();
    await db.close();
  });

  test('read returns defaults 8/22/7 on empty table', () async {
    final s = await store.read();
    expect(s.visibleStartHour, 8);
    expect(s.visibleEndHour, 22);
    expect(s.urgencyWindowDays, 7);
  });

  test('write persists and read returns the new values', () async {
    await store.write(const AppSettings(
      visibleStartHour: 6,
      visibleEndHour: 23,
      urgencyWindowDays: 14,
    ));
    final s = await store.read();
    expect(s.visibleStartHour, 6);
    expect(s.visibleEndHour, 23);
    expect(s.urgencyWindowDays, 14);
  });

  test('watch emits current settings and again after write', () async {
    final emissions = <AppSettings>[];
    final sub = store.watch().listen(emissions.add);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await store.write(const AppSettings(urgencyWindowDays: 3));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await sub.cancel();
    expect(emissions.length, 2);
    expect(emissions.first.urgencyWindowDays, 7);
    expect(emissions.last.urgencyWindowDays, 3);
  });
}
