import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../leaderboard/domain/leaderboard_models.dart';
import '../../leaderboard/providers/season_rank_provider.dart';
import '../providers/map_state_notifier.dart';

/// [Dev A] Dual-Metric Live HUD: % Lãnh thổ chiếm đóng & % Km cống hiến của 5 trường.
class PercentDominanceBar extends ConsumerWidget {
  const PercentDominanceBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scores = ref.watch(seasonRankProvider).valueOrNull ?? const <CampusScore>[];
    final cells = ref.watch(mapStateNotifierProvider);
    final owned = cells.values.where((c) => !c.isNeutral).length;
    final totalKm = scores.fold<double>(0, (sum, s) => sum + s.totalKm);
    final session = ref.watch(authSessionProvider);
    final myCode = session is AuthSignedIn ? session.user.university.shortCode : null;
    final mine = scores.where((s) => s.shortName == myCode).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: sisoCard().copyWith(
        color: SisoColors.card.withValues(alpha: 0.95),
        boxShadow: const [BoxShadow(color: Color(0x0F000000), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Text('Mùa giải hiện tại', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: SisoColors.tint, borderRadius: BorderRadius.circular(99)),
                child: const Text('Bình Thạnh',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: SisoColors.primary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _MetricRow(
            label: '% Lãnh thổ chiếm đóng',
            value: '$owned / ${cells.length} ô',
            parts: [for (final s in scores) (s.color, s.territoryPct)],
          ),
          const SizedBox(height: 10),
          _MetricRow(
            label: '% Km cống hiến',
            value: '${viDecimal(totalKm)} km',
            parts: [for (final s in scores) (s.color, s.mileagePct)],
          ),
          if (mine != null) ...[
            const SizedBox(height: 10),
            const Divider(height: 1, color: SisoColors.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                CampusDot(color: mine.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${mine.shortName} · Đất ${viDecimal(mine.territoryPct)}% · Km ${viDecimal(mine.mileagePct)}%',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SisoColors.primary),
                  ),
                ),
                for (final s in scores)
                  if (s != mine)
                    Padding(padding: const EdgeInsets.only(left: 4), child: CampusDot(color: s.color, size: 8)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value, required this.parts});

  final String label;
  final String value;
  final List<(Color, double)> parts;

  @override
  Widget build(BuildContext context) {
    final visible = parts.where((p) => p.$2 > 0).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: SisoColors.body)),
            ),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          height: 12,
          padding: const EdgeInsets.all(1.5),
          decoration: BoxDecoration(color: SisoColors.border, borderRadius: BorderRadius.circular(99)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: Row(
              children: [
                for (final (i, (color, pct)) in visible.indexed) ...[
                  if (i > 0) const SizedBox(width: 1),
                  Expanded(
                    flex: (pct * 10).round().clamp(1, 1000),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        border: isLightSwatch(color)
                            ? const Border.symmetric(horizontal: BorderSide(color: SisoColors.lightSwatchBorder))
                            : null,
                      ),
                    ),
                  ),
                ],
                // Phần chưa trường nào chiếm (tổng < 100%)
                if (100 - visible.fold<double>(0, (s, p) => s + p.$2) case final rest when rest > 0.5)
                  Expanded(flex: (rest * 10).round(), child: const SizedBox()),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
