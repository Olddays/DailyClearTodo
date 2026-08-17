import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../domain/day_archive.dart';

final historyProvider = FutureProvider.autoDispose<List<DayArchive>>((ref) {
  final now = DateTime.now();
  return ref.read(taskRepositoryProvider).getHistory(
        start: now.subtract(const Duration(days: 30)),
        end: now,
      );
});

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('历史复盘')),
      body: historyAsync.when(
        data: (archives) {
          if (archives.isEmpty) {
            return const Center(child: Text('还没有历史记录\n（每天结束后会自动归档）', textAlign: TextAlign.center));
          }
          final totalTasks = archives.fold<int>(0, (s, a) => s + a.totalTasks);
          final doneTasks = archives.fold<int>(0, (s, a) => s + a.doneTasks);
          final overallRate = totalTasks == 0 ? 0.0 : doneTasks / totalTasks;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(historyProvider),
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '近 30 天：共规划 $totalTasks 个任务，完成 $doneTasks 个，完成率 ${(overallRate * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...archives.map((a) => _ArchiveTile(archive: a)),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  final DayArchive archive;
  const _ArchiveTile({required this.archive});

  @override
  Widget build(BuildContext context) {
    final rate = (archive.completionRate * 100).toStringAsFixed(0);
    final dateStr = '${archive.archiveDate.year}-${archive.archiveDate.month.toString().padLeft(2, '0')}-${archive.archiveDate.day.toString().padLeft(2, '0')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(dateStr),
        subtitle: Text('${archive.doneTasks}/${archive.totalTasks} 完成 · 番茄钟 ${archive.totalPomodoros} 个'),
        trailing: Text(
          '$rate%',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: archive.completionRate >= 0.7
                    ? Colors.green
                    : archive.completionRate >= 0.4
                        ? Colors.orange
                        : Colors.red,
                fontWeight: FontWeight.bold,
              ),
        ),
      ),
    );
  }
}
