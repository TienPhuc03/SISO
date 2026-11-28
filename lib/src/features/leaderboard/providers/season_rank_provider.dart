import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/leaderboard_repository.dart';
import '../domain/leaderboard_models.dart';

final leaderboardRepositoryProvider = Provider<LeaderboardRepository>((ref) => LeaderboardRepository());

/// Cụm của Trường Sinh viên đang đăng nhập; null nếu chưa chọn Trường.
final myClusterProvider = Provider<String?>((ref) {
  final session = ref.watch(authSessionProvider);
  return session is AuthSignedIn ? session.user.university?.clusterCode : null;
});

/// Bảng xếp hạng Cụm của chính Sinh viên (thanh % trên Bản đồ). Dùng autoDispose để mở lại là lấy số mới.
final seasonRankProvider = FutureProvider.autoDispose<List<CampusScore>>(
  (ref) => ref.watch(leaderboardRepositoryProvider).fetchScores(cluster: ref.watch(myClusterProvider)),
);

/// Cụm đang xem trên màn Bảng xếp hạng; mặc định Cụm của mình (null = Cụm đầu danh mục).
final leaderboardClusterProvider = StateProvider.autoDispose<String?>((ref) => ref.watch(myClusterProvider));

final clusterRankProvider = FutureProvider.autoDispose.family<List<CampusScore>, String?>(
  (ref, cluster) => ref.watch(leaderboardRepositoryProvider).fetchScores(cluster: cluster),
);

final hallOfFameProvider = FutureProvider.autoDispose.family<List<HallOfFameEntry>, String?>(
  (ref, cluster) => ref.watch(leaderboardRepositoryProvider).fetchHallOfFame(cluster: cluster),
);

final activeSeasonProvider = FutureProvider.autoDispose<ActiveSeason?>(
  (ref) => ref.watch(leaderboardRepositoryProvider).fetchActiveSeason(),
);
