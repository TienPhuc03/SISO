import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';

/// Thẻ Đại sảnh Danh vọng: Quán quân của các Mùa giải đã qua, mới nhất trước.
class HallOfFameCard extends ConsumerWidget {
  const HallOfFameCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, color: Colors.amber),
                const SizedBox(width: 8),
                Text('Đại sảnh Danh vọng', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ref.watch(hallOfFameProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _Retry(
                    message: 'Không tải được Đại sảnh Danh vọng.',
                    onRetry: () => ref.invalidate(hallOfFameProvider),
                  ),
                  data: (entries) => entries.isEmpty
                      ? const Text('Chưa có Quán quân. Mùa giải đầu tiên vẫn đang diễn ra.')
                      : Column(children: [for (final e in entries) _ChampionRow(entry: e)]),
                ),
          ],
        ),
      ),
    );
  }
}

class _ChampionRow extends StatelessWidget {
  const _ChampionRow({required this.entry});

  final HallOfFameEntry entry;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(radius: 8, backgroundColor: entry.color),
      title: Text(entry.championName),
      subtitle: Text('Mùa ${entry.seasonNumber}'),
      trailing: Text('${entry.compositePct.toStringAsFixed(1)}%'),
    );
  }
}

class _Retry extends StatelessWidget {
  const _Retry({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(message)),
        TextButton(onPressed: onRetry, child: const Text('Thử lại')),
      ],
    );
  }
}
