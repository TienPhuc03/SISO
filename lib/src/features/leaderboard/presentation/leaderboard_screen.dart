import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';
import 'hall_of_fame_card.dart';

/// Màn hình Bảng xếp hạng Mùa giải: Sức mạnh Tổng hợp của 5 Trường và Đại sảnh Danh vọng.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scores = ref.watch(seasonRankProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Bảng Xếp Hạng Mùa Giải')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hallOfFameProvider);
          ref.invalidate(seasonRankProvider);
          await ref.read(seasonRankProvider.future).catchError((_) => <CampusScore>[]);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const HallOfFameCard(),
            const SizedBox(height: 16),
            Text('Sức mạnh Tổng hợp (50% Đất + 50% Km)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...scores.when(
              loading: () => const [Center(child: CircularProgressIndicator())],
              error: (_, __) => [
                const Text('Không tải được bảng xếp hạng.', key: Key('leaderboard_error')),
                TextButton(
                  onPressed: () => ref.invalidate(seasonRankProvider),
                  child: const Text('Thử lại'),
                ),
              ],
              data: (rows) => rows.isEmpty
                  ? const [Text('Chưa có dữ liệu xếp hạng.')]
                  : [for (final (i, row) in rows.indexed) _ScoreCard(rank: i + 1, score: row)],
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.rank, required this.score});

  final int rank;
  final CampusScore score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('#$rank', style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                CircleAvatar(radius: 8, backgroundColor: score.color),
                const SizedBox(width: 8),
                Expanded(child: Text(score.shortName, style: theme.textTheme.titleMedium)),
                Text('${score.compositePct.toStringAsFixed(1)}%', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (score.compositePct / 100).clamp(0, 1).toDouble(),
              color: score.color,
              minHeight: 6,
            ),
            const SizedBox(height: 8),
            Text(
              'Đất ${score.territoryPct.toStringAsFixed(1)}% · '
              'Km ${score.mileagePct.toStringAsFixed(1)}% (${score.totalKm.toStringAsFixed(1)} km)',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
