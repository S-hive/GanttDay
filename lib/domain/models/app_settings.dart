class AppSettings {
  const AppSettings({
    this.visibleStartHour = 8,
    this.visibleEndHour = 22,
    this.urgencyWindowDays = 7,
  });

  final int visibleStartHour;
  final int visibleEndHour;
  final int urgencyWindowDays;

  AppSettings copyWith({
    int? visibleStartHour,
    int? visibleEndHour,
    int? urgencyWindowDays,
  }) {
    return AppSettings(
      visibleStartHour: visibleStartHour ?? this.visibleStartHour,
      visibleEndHour: visibleEndHour ?? this.visibleEndHour,
      urgencyWindowDays: urgencyWindowDays ?? this.urgencyWindowDays,
    );
  }
}
