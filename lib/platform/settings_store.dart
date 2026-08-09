import '../domain/models/app_settings.dart';

abstract class SettingsStore {
  Stream<AppSettings> watch();

  Future<AppSettings> read();

  Future<void> write(AppSettings settings);
}
