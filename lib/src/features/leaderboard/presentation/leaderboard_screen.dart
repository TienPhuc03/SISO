import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/permissions/notification_permission.dart';
import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../forum/presentation/forum_screen.dart';
import '../../map/presentation/siso_bottom_nav.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../tracking/presentation/active_run_screen.dart';
import '../../university/domain/university_catalog.dart';
import '../../university/providers/university_providers.dart';
import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';
import 'hall_of_fame_card.dart';
import 'season_banner.dart';

/// Tên Cụm ngắn cho chip: bỏ phần trong ngoặc ("Cụm Trung tâm (Quận 1, 3, 5, 10)" -> "Cụm Trung tâm").
String shortClusterName(String name) => name.split('(').first.trim();

/// Màn hình Bảng xếp hạng Mùa giải theo Cụm: Sức mạnh Tổng hợp các Trường trong Cụm và Đại sảnh Danh vọng của Cụm.
class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(universityCatalogProvider).valueOrNull;
    final cluster = ref.watch(leaderboardClusterProvider) ?? catalog?.clusters.firstOrNull?.code;
    final scores = ref.watch(clusterRankProvider(cluster));
    final session = ref.watch(authSessionProvider);
    final myId = session is AuthSignedIn ? session.user.university?.id : null;
    // Chưa chọn Trường (mở từ màn chọn Trường): chỉ xem, không có thanh điều hướng để chạy.
    final canRun = session is AuthSignedIn && (session.user.university != null || session.user.isAdmin);

    // Lần đầu mở Xếp hạng: xin quyền thông báo (nhắc Ô đất sắp hết Độ bền).
    return NotificationPermissionPrompt(
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(hallOfFameProvider(cluster));
                  ref.invalidate(activeSeasonProvider);
                  ref.invalidate(clusterRankProvider(cluster));
                  await ref.read(clusterRankProvider(cluster).future).catchError((_) => <CampusScore>[]);
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 140),
                  children: [
                    Row(
                      children: [
                        if (!canRun)
                          IconButton(
                            tooltip: 'Quay lại',
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                        const Text('Bảng xếp hạng', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    const SeasonBanner(),
                    if (catalog != null) ...[
                      const SizedBox(height: 12),
                      _ClusterChips(catalog: catalog, selected: cluster),
                    ],
                    const SizedBox(height: 16),
                    HallOfFameCard(cluster: cluster),
                    const SizedBox(height: 20),
                    Text(
                      scores.valueOrNull?.firstOrNull?.clusterHasArena == false
                          ? 'Sức mạnh Tổng hợp (100% Km)'
                          : 'Sức mạnh Tổng hợp (50% Đất + 50% Km)',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                    if (scores.valueOrNull?.firstOrNull?.clusterHasArena == false)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('Cụm chưa mở Đấu trường: xếp hạng theo Quỹ Km.',
                            key: Key('cluster_no_arena'), style: TextStyle(fontSize: 12.5, color: SisoColors.body)),
                      ),
                    const SizedBox(height: 12),
                    ...scores.when(
                      loading: () => const [Center(child: CircularProgressIndicator())],
                      error: (_, __) => [
                        const Text('Không tải được bảng xếp hạng.', key: Key('leaderboard_error')),
                        TextButton(
                          onPressed: () => ref.invalidate(clusterRankProvider(cluster)),
                          child: const Text('Thử lại'),
                        ),
                      ],
                      data: (rows) => rows.isEmpty
                          ? const [Text('Cụm này chưa có Trường nào.')]
                          : [
                              for (final (i, row) in rows.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _ScoreCard(rank: i + 1, score: row, isMine: row.universityId == myId),
                                ),
                            ],
                    ),
                  ],
                ),
              ),
            ),
            if (canRun)
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
                  onForum: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute<void>(builder: (_) => const ForumScreen())),
                  onProfile: () => Navigator.of(context)
                      .pushReplacement(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chọn Cụm để xem; mặc định Cụm của mình.
class _ClusterChips extends ConsumerWidget {
  const _ClusterChips({required this.catalog, required this.selected});

  final UniversityCatalog catalog;
  final String? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myClusterProvider);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final c in catalog.clusters) ...[
            ChoiceChip(
              key: Key('cluster_${c.code}'),
              label: Text(shortClusterName(c.name) + (c.code == mine ? ' · của bạn' : '')),
              tooltip: c.name,
              selected: c.code == selected,
              onSelected: (_) => ref.read(leaderboardClusterProvider.notifier).state = c.code,
            ),
            const SizedBox(width: 8),
          ],
        ],
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
                    overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
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
