import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/siso_theme.dart';
import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';

/// Thẻ Đại sảnh Danh vọng: Quán quân của [cluster] qua các Mùa giải, mới nhất trước.
class HallOfFameCard extends ConsumerWidget {
  const HallOfFameCard({super.key, this.cluster});

  final String? cluster;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: sisoCard(),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events_outlined, color: SisoColors.primary, size: 20),
                SizedBox(width: 8),
                Text('Đại sảnh Danh vọng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1, color: SisoColors.border),
            const SizedBox(height: 12),
            ref.watch(hallOfFameProvider(cluster)).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (_, __) => _Retry(
                    message: 'Không tải được Đại sảnh Danh vọng.',
                    onRetry: () => ref.invalidate(hallOfFameProvider(cluster)),
                  ),
                  data: (entries) => entries.isEmpty
                      ? const Text('Chưa có Quán quân của Cụm này.')
                      : Column(children: [for (final e in entries) _ChampionRow(entry: e)]),
                ),
          ],
        ),
    );
  }
}

class _ChampionRow extends StatelessWidget {
  const _ChampionRow({required this.entry});

  final HallOfFameEntry entry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          CampusDot(color: entry.color),
          const SizedBox(width: 8),
          Text(entry.championName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const Text('  ·  ', style: TextStyle(fontSize: 13, color: SisoColors.caption)),
          Text('Mùa ${entry.seasonNumber}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: SisoColors.body)),
          const Spacer(),
          Text('${viDecimal(entry.compositePct)}%', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
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
