import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/leaderboard_repository.dart';
import '../domain/leaderboard_models.dart';

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) => LeaderboardRepository());

/// Dùng autoDispose để mỗi lần mở màn hình lại lấy số mới.
final seasonRankProvider = FutureProvider.autoDispose<List<CampusScore>>(
  (ref) => ref.watch(leaderboardRepositoryProvider).fetchScores(),
);

final hallOfFameProvider = FutureProvider.autoDispose<List<HallOfFameEntry>>(
  (ref) => ref.watch(leaderboardRepositoryProvider).fetchHallOfFame(),
);
