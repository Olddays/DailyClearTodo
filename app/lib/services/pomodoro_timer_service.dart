import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/providers.dart';
import 'notification_service.dart';

const _defaultDuration = Duration(minutes: 25);
const _prefsTaskId = 'pomodoro_active_task_id';
const _prefsTaskTitle = 'pomodoro_active_task_title';
const _prefsStartedAtMs = 'pomodoro_started_at_ms';
const _prefsEndsAtMs = 'pomodoro_ends_at_ms';

class PomodoroTimerState {
  final String taskId;
  final String taskTitle;
  final DateTime startedAt;
  final DateTime endsAt;

  const PomodoroTimerState({
    required this.taskId,
    required this.taskTitle,
    required this.startedAt,
    required this.endsAt,
  });

  Duration remaining(DateTime now) {
    final diff = endsAt.difference(now);
    return diff.isNegative ? Duration.zero : diff;
  }
}

final pomodoroTimerProvider = NotifierProvider<PomodoroTimerNotifier, PomodoroTimerState?>(
  PomodoroTimerNotifier.new,
);

/// Runs entirely client-side on wall-clock time (start/end timestamps, not a
/// tick counter) so backgrounding or app restarts can't cause drift -- on
/// [build], any timer that was persisted before the app was killed is either
/// resumed (if still running) or completed immediately (if its end time already
/// passed while the app was closed). Completion writes directly to Supabase;
/// it never goes through the chat Edge Function/LLM.
class PomodoroTimerNotifier extends Notifier<PomodoroTimerState?> {
  Timer? _ticker;

  @override
  PomodoroTimerState? build() {
    ref.onDispose(() => _ticker?.cancel());
    _restoreIfAny();
    return null;
  }

  Future<void> _restoreIfAny() async {
    final prefs = await SharedPreferences.getInstance();
    final taskId = prefs.getString(_prefsTaskId);
    final endsAtMs = prefs.getInt(_prefsEndsAtMs);
    if (taskId == null || endsAtMs == null) return;

    final endsAt = DateTime.fromMillisecondsSinceEpoch(endsAtMs);
    final startedAt = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_prefsStartedAtMs)!);
    final title = prefs.getString(_prefsTaskTitle) ?? '';

    if (!endsAt.isAfter(DateTime.now())) {
      // The app was closed/killed past completion -- finish it now rather than
      // silently losing the session.
      await _complete(taskId: taskId, taskTitle: title, startedAt: startedAt, endsAt: endsAt, outcome: 'completed');
      return;
    }
    state = PomodoroTimerState(taskId: taskId, taskTitle: title, startedAt: startedAt, endsAt: endsAt);
    _startTicking();
  }

  Future<void> start({required String taskId, required String taskTitle, Duration duration = _defaultDuration}) async {
    if (state != null) return; // one active timer at a time
    final startedAt = DateTime.now();
    final endsAt = startedAt.add(duration);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTaskId, taskId);
    await prefs.setString(_prefsTaskTitle, taskTitle);
    await prefs.setInt(_prefsStartedAtMs, startedAt.millisecondsSinceEpoch);
    await prefs.setInt(_prefsEndsAtMs, endsAt.millisecondsSinceEpoch);

    state = PomodoroTimerState(taskId: taskId, taskTitle: taskTitle, startedAt: startedAt, endsAt: endsAt);
    _startTicking();
  }

  /// User-initiated early stop -- logged as 'interrupted' with the actual
  /// elapsed duration, not the planned 25 minutes.
  Future<void> cancel() async {
    final current = state;
    if (current == null) return;
    await _complete(
      taskId: current.taskId,
      taskTitle: current.taskTitle,
      startedAt: current.startedAt,
      endsAt: DateTime.now(),
      outcome: 'interrupted',
    );
  }

  void _startTicking() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = state;
      if (current == null) {
        _ticker?.cancel();
        return;
      }
      if (!current.endsAt.isAfter(DateTime.now())) {
        _complete(
          taskId: current.taskId,
          taskTitle: current.taskTitle,
          startedAt: current.startedAt,
          endsAt: current.endsAt,
          outcome: 'completed',
        );
      } else {
        // Re-assign to force listeners (the countdown display) to rebuild.
        state = current;
      }
    });
  }

  Future<void> _complete({
    required String taskId,
    required String taskTitle,
    required DateTime startedAt,
    required DateTime endsAt,
    required String outcome,
  }) async {
    _ticker?.cancel();
    state = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTaskId);
    await prefs.remove(_prefsTaskTitle);
    await prefs.remove(_prefsStartedAtMs);
    await prefs.remove(_prefsEndsAtMs);

    await ref.read(taskRepositoryProvider).logPomodoroAndPromptCheckIn(
          taskId: taskId,
          startedAt: startedAt,
          endedAt: endsAt,
          outcome: outcome,
        );

    if (outcome == 'completed') {
      await NotificationService.instance.showPomodoroComplete(taskTitle);
    }
  }
}
