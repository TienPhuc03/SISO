import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/siso_theme.dart';
import '../domain/leaderboard_models.dart';
import '../providers/season_rank_provider.dart';

/// Dòng dưới tiêu đề Bảng xếp hạng: "Mùa N · còn X ngày Y giờ · kết thúc dd/mm", đếm ngược mỗi phút.
class SeasonBanner extends ConsumerStatefulWidget {
  const SeasonBanner({super.key});

  @override
  ConsumerState<SeasonBanner> createState() => _SeasonBannerState();
}

class _SeasonBannerState extends ConsumerState<SeasonBanner> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const plain = TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: SisoColors.body);
    final season = ref.watch(activeSeasonProvider);

    // Đang tải hoặc lỗi mạng: giữ dòng cũ, không chặn bảng điểm.
    final s = season.valueOrNull;
    if (s == null) {
      return Text(season.hasValue ? 'Đang chờ mùa mới' : 'Mùa giải hiện tại',
          key: const Key('season_banner'), style: plain);
    }

    final left = s.endsAt.difference(DateTime.now());
    final end = '${s.endDate.day.toString().padLeft(2, '0')}/${s.endDate.month.toString().padLeft(2, '0')}';
    if (left <= Duration.zero) {
      return Text('Mùa ${s.number} · đang tổng kết', key: const Key('season_banner'), style: plain);
    }

    final urgent = left < const Duration(days: 1);
    return Text(
      'Mùa ${s.number} · còn ${formatSeasonRemaining(left)} · kết thúc $end',
      key: const Key('season_banner'),
      style: urgent ? plain.copyWith(color: SisoColors.danger, fontWeight: FontWeight.w700) : plain,
    );
  }
}
