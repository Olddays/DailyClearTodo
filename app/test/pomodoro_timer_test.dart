import 'package:flutter_test/flutter_test.dart';

import 'package:dailyclear/services/pomodoro_timer_service.dart';

void main() {
  group('PomodoroTimerState.remaining', () {
    test('returns the gap between now and endsAt while still running', () {
      final now = DateTime(2026, 7, 27, 10, 0, 0);
      final state = PomodoroTimerState(
        taskId: 't1',
        taskTitle: 'Test',
        startedAt: now,
        endsAt: now.add(const Duration(minutes: 25)),
      );
      expect(state.remaining(now.add(const Duration(minutes: 10))), const Duration(minutes: 15));
    });

    test('clamps to zero once past endsAt -- never goes negative', () {
      final now = DateTime(2026, 7, 27, 10, 0, 0);
      final state = PomodoroTimerState(
        taskId: 't1',
        taskTitle: 'Test',
        startedAt: now,
        endsAt: now.add(const Duration(minutes: 25)),
      );
      expect(state.remaining(now.add(const Duration(minutes: 40))), Duration.zero);
    });

    test('is wall-clock based: identical result regardless of how many ticks were missed', () {
      final now = DateTime(2026, 7, 27, 10, 0, 0);
      final state = PomodoroTimerState(
        taskId: 't1',
        taskTitle: 'Test',
        startedAt: now,
        endsAt: now.add(const Duration(minutes: 25)),
      );
      // Simulates the app being backgrounded/killed for a while -- the check is
      // purely startedAt/endsAt vs current wall clock, so no drift accumulates.
      final afterLongBackground = now.add(const Duration(minutes: 20));
      expect(state.remaining(afterLongBackground), const Duration(minutes: 5));
    });
  });
}
