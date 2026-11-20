import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/notification_permission.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../map/presentation/siso_bottom_nav.dart';
import '../../tracking/presentation/active_run_screen.dart';
import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';
import 'hall_of_fame_card.dart';

/// Màn hình Bảng xếp hạng Mùa giải: Sức mạnh Tổng hợp của 5 Trường và Đại sảnh Danh vọng.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scores = ref.watch(seasonRankProvider);
    final session = ref.watch(authSessionProvider);
    final myCode = session is AuthSignedIn ? session.user.university.shortCode : null;

    // Lần đầu mở Xếp hạng: xin quyền thông báo (nhắc Ô đất sắp hết Độ bền).
    return NotificationPermissionPrompt(
      child: Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(hallOfFameProvider);
                ref.invalidate(seasonRankProvider);
                await ref.read(seasonRankProvider.future).catchError((_) => <CampusScore>[]);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                children: [
                  const Text('Bảng xếp hạng', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  const Text('Mùa giải hiện tại',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SisoColors.body)),
                  const SizedBox(height: 16),
                  const HallOfFameCard(),
                  const SizedBox(height: 20),
                  const Text('Sức mạnh Tổng hợp (50% Đất + 50% Km)',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
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
                        : [
                            for (final (i, row) in rows.indexed)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _ScoreCard(rank: i + 1, score: row, isMine: row.shortName == myCode),
                              ),
                          ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SisoBottomNav(
              active: SisoTab.leaderboard,
              onMap: () => Navigator.of(context).maybePop(),
              onRun: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute<void>(builder: (_) => const ActiveRunScreen()),
              ),
              onLeaderboard: () {},
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.rank, required this.score, required this.isMine});

  final int rank;
  final CampusScore score;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: sisoCard(
        radius: 16,
        border: isMine ? SisoColors.primary : SisoColors.border,
        width: isMine ? 2 : 1,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('$rank', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 10),
              CampusDot(color: score.color, size: 12),
              const SizedBox(width: 10),
              Flexible(
                child: Text(score.shortName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              if (isMine) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: SisoColors.tint, borderRadius: BorderRadius.circular(99)),
                  child: const Text('Trường của bạn',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SisoColors.primary)),
                ),
              ],
              const Spacer(),
              Text('${viDecimal(score.compositePct)}%',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Container(
              height: 6,
              color: SisoColors.track,
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (score.compositePct / 100).clamp(0, 1).toDouble(),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: score.color,
                    borderRadius: BorderRadius.circular(99),
                    border: isLightSwatch(score.color) ? Border.all(color: SisoColors.lightSwatchBorder) : null,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text.rich(
            TextSpan(
              text: 'Đất ${viDecimal(score.territoryPct)}% · Km ${viDecimal(score.mileagePct)}% ',
              children: [
                TextSpan(
                  text: '(${viDecimal(score.totalKm)} km)',
                  style: const TextStyle(color: SisoColors.caption, fontWeight: FontWeight.w400),
                ),
              ],
            ),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: SisoColors.body),
          ),
        ],
      ),
    );
  }
}
