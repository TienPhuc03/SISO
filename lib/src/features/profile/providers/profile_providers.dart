import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/profile_repository.dart';
import '../domain/profile_models.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) => ProfileRepository());

/// Không autoDispose: nút ảnh đại diện trên Bản đồ dùng chung; đổi nickname / ảnh thì invalidate.
/// Theo dõi id Sinh viên đang đăng nhập để đăng xuất / đổi tài khoản không hiện hồ sơ của người trước.
final profileProvider = FutureProvider<Profile>((ref) {
  ref.watch(authSessionProvider.select((s) => s is AuthSignedIn ? s.user.id : null));
  return ref.watch(profileRepositoryProvider).fetchProfile();
});

/// autoDispose: mỗi lần mở Hồ sơ lấy lịch sử mới (có Phiên vừa chạy).
final runHistoryProvider =
    FutureProvider.autoDispose<List<RunSummary>>((ref) => ref.watch(profileRepositoryProvider).fetchRuns());

final runDetailProvider = FutureProvider.autoDispose.family<RunDetail, String>(
  (ref, sessionId) => ref.watch(profileRepositoryProvider).fetchRun(sessionId),
);
