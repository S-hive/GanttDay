import '../time/wall_clock.dart';

class Task {
  const Task({
    required this.id,
    required this.title,
    required this.plannedStart,
    required this.plannedEnd,
    this.actualStart,
    this.actualEnd,
    this.isDone = false,
    this.primaryTagId,
    required this.autoHue,
    this.overrideHue,
    this.notes,
    required this.createdAt,
  });

  final String id;
  final String title;
  final WallMinutes plannedStart;
  final WallMinutes plannedEnd;
  final WallMinutes? actualStart;
  final WallMinutes? actualEnd;
  final bool isDone;
  final String? primaryTagId;
  final int autoHue;
  final int? overrideHue;
  final String? notes;
  final WallMinutes createdAt;

  Task copyWith({
    String? title,
    WallMinutes? plannedStart,
    WallMinutes? plannedEnd,
    WallMinutes? actualStart,
    WallMinutes? actualEnd,
    bool? isDone,
    String? primaryTagId,
    int? overrideHue,
    String? notes,
    bool clearActuals = false,
    bool clearPrimaryTag = false,
    bool clearOverrideHue = false,
    bool clearNotes = false,
  }) {
    return Task(
      id: id,
      title: title ?? this.title,
      plannedStart: plannedStart ?? this.plannedStart,
      plannedEnd: plannedEnd ?? this.plannedEnd,
      actualStart: clearActuals ? null : (actualStart ?? this.actualStart),
      actualEnd: clearActuals ? null : (actualEnd ?? this.actualEnd),
      isDone: isDone ?? this.isDone,
      primaryTagId:
          clearPrimaryTag ? null : (primaryTagId ?? this.primaryTagId),
      autoHue: autoHue,
      overrideHue: clearOverrideHue ? null : (overrideHue ?? this.overrideHue),
      notes: clearNotes ? null : (notes ?? this.notes),
      createdAt: createdAt,
    );
  }
}
