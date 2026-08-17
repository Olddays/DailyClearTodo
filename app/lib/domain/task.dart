enum TaskStatus { pending, inProgress, done, abandoned }

TaskStatus taskStatusFromString(String value) => switch (value) {
      'pending' => TaskStatus.pending,
      'in_progress' => TaskStatus.inProgress,
      'done' => TaskStatus.done,
      _ => TaskStatus.abandoned,
    };

String taskStatusToString(TaskStatus status) => switch (status) {
      TaskStatus.pending => 'pending',
      TaskStatus.inProgress => 'in_progress',
      TaskStatus.done => 'done',
      TaskStatus.abandoned => 'abandoned',
    };

/// Mirrors a row in the `tasks` table. "Today" vs "history" is just which
/// [taskDate] this row happens to have -- there is no separate table.
class Task {
  final String id;
  final String title;
  final TaskStatus status;
  final int position;
  final int? plannedPomodoros;
  final int pomodorosUsed;
  final DateTime taskDate;

  Task({
    required this.id,
    required this.title,
    required this.status,
    required this.position,
    required this.plannedPomodoros,
    required this.pomodorosUsed,
    required this.taskDate,
  });

  factory Task.fromRow(Map<String, dynamic> row) {
    return Task(
      id: row['id'] as String,
      title: row['title'] as String,
      status: taskStatusFromString(row['status'] as String),
      position: row['position'] as int? ?? 0,
      plannedPomodoros: row['planned_pomodoros'] as int?,
      pomodorosUsed: row['pomodoros_used'] as int? ?? 0,
      taskDate: DateTime.parse(row['task_date'] as String),
    );
  }
}
