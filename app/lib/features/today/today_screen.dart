import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/task.dart';
import '../../services/pomodoro_timer_service.dart';

final todayTasksStreamProvider = StreamProvider.autoDispose<List<Task>>((ref) {
  return ref.watch(taskRepositoryProvider).watchTodayTasks();
});

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(todayTasksStreamProvider);
    final timerState = ref.watch(pomodoroTimerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('今日看板')),
      body: Column(
        children: [
          if (timerState != null) _ActiveTimerBanner(state: timerState),
          Expanded(
            child: tasksAsync.when(
              data: (tasks) {
                if (tasks.isEmpty) {
                  return const Center(child: Text('今天还没有任务，去跟日清聊聊吧'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: tasks.length,
                  itemBuilder: (context, i) => _TaskCard(task: tasks[i], timerState: timerState),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('加载失败: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveTimerBanner extends ConsumerStatefulWidget {
  final PomodoroTimerState state;
  const _ActiveTimerBanner({required this.state});

  @override
  ConsumerState<_ActiveTimerBanner> createState() => _ActiveTimerBannerState();
}

class _ActiveTimerBannerState extends ConsumerState<_ActiveTimerBanner> {
  Timer? _uiTicker;

  @override
  void initState() {
    super.initState();
    // Independent 1s UI refresh -- the notifier's own state only changes once
    // per tick, but re-reading remaining() here keeps the displayed mm:ss fresh
    // even between notifier rebuilds.
    _uiTicker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _uiTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.state.remaining(DateTime.now());
    final mm = remaining.inMinutes.toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.primaryContainer,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '正在进行：${widget.state.taskTitle}  $mm:$ss',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(pomodoroTimerProvider.notifier).cancel(),
            child: const Text('中止'),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final Task task;
  final PomodoroTimerState? timerState;
  const _TaskCard({required this.task, required this.timerState});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isTimerRunning = timerState != null;
    final isThisTaskTiming = timerState?.taskId == task.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          decoration: task.status == TaskStatus.done ? TextDecoration.lineThrough : null,
                        ),
                  ),
                ),
                _StatusChip(status: task.status),
              ],
            ),
            const SizedBox(height: 4),
            Text('已完成番茄钟: ${task.pomodorosUsed}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (task.status != TaskStatus.done && task.status != TaskStatus.abandoned)
                  FilledButton.icon(
                    onPressed: isTimerRunning
                        ? null
                        : () => ref.read(pomodoroTimerProvider.notifier).start(taskId: task.id, taskTitle: task.title),
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: Text(isThisTaskTiming ? '进行中…' : '开始番茄钟'),
                  ),
                if (task.status != TaskStatus.done)
                  OutlinedButton(
                    onPressed: () => ref.read(taskRepositoryProvider).updateTaskStatus(task.id, TaskStatus.done),
                    child: const Text('标记完成'),
                  ),
                if (task.status == TaskStatus.pending || task.status == TaskStatus.inProgress)
                  OutlinedButton(
                    onPressed: () => ref.read(taskRepositoryProvider).updateTaskStatus(task.id, TaskStatus.abandoned),
                    child: const Text('放弃'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final TaskStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      TaskStatus.pending => ('待开始', Colors.grey),
      TaskStatus.inProgress => ('进行中', Colors.blue),
      TaskStatus.done => ('已完成', Colors.green),
      TaskStatus.abandoned => ('已放弃', Colors.orange),
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      backgroundColor: color.withValues(alpha: 0.15),
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
    );
  }
}
