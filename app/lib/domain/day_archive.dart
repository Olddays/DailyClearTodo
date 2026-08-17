/// Mirrors a row in `day_archives` -- written once by the server-side archive
/// sweep, read-only from the client (RLS only grants select on this table).
class DayArchive {
  final DateTime archiveDate;
  final int totalTasks;
  final int doneTasks;
  final double completionRate;
  final int totalPomodoros;

  DayArchive({
    required this.archiveDate,
    required this.totalTasks,
    required this.doneTasks,
    required this.completionRate,
    required this.totalPomodoros,
  });

  factory DayArchive.fromRow(Map<String, dynamic> row) {
    return DayArchive(
      archiveDate: DateTime.parse(row['archive_date'] as String),
      totalTasks: row['total_tasks'] as int,
      doneTasks: row['done_tasks'] as int,
      completionRate: (row['completion_rate'] as num).toDouble(),
      totalPomodoros: row['total_pomodoros'] as int? ?? 0,
    );
  }
}
