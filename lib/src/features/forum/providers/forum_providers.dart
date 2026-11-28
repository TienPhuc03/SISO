import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../data/forum_repository.dart';
import '../domain/forum_models.dart';

final forumRepositoryProvider = Provider<ForumRepository>((ref) => ForumRepository());

final forumScopeProvider = StateProvider.autoDispose<ForumScope>((ref) => ForumScope.all);

const forumPageSize = 20;

/// Bảng tin theo bộ lọc: tải trang đầu, "Tải thêm" nối trang sau; tym cập nhật tại chỗ.
class ForumFeedNotifier extends StateNotifier<AsyncValue<List<ForumPost>>> {
  ForumFeedNotifier(this._repo, {this.cluster, this.universityId}) : super(const AsyncLoading()) {
    refresh();
  }

  final ForumRepository _repo;
  final String? cluster;
  final String? universityId;
  bool hasMore = true;
  bool _loadingMore = false;

  Future<void> refresh() async {
    try {
      final page = await _repo.feed(cluster: cluster, universityId: universityId, limit: forumPageSize);
      hasMore = page.length == forumPageSize;
      if (mounted) state = AsyncData(page);
    } catch (e, st) {
      if (mounted) state = AsyncError(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || current.isEmpty || !hasMore || _loadingMore) return;
    _loadingMore = true;
    try {
      final page = await _repo.feed(
        cluster: cluster,
        universityId: universityId,
        before: current.last.createdAt,
        limit: forumPageSize,
      );
      hasMore = page.length == forumPageSize;
      if (mounted) state = AsyncData([...current, ...page]);
    } finally {
      _loadingMore = false;
    }
  }

  /// Đổi tym ngay trên màn (lạc quan); server lỗi thì trả lại như cũ và ném lỗi để màn hình báo.
  Future<void> toggleLike(ForumPost post) async {
    final liked = !post.likedByMe;
    replace(post.copyWith(likedByMe: liked, likeCount: post.likeCount + (liked ? 1 : -1)));
    try {
      final count = await _repo.setLiked(post.id, liked);
      replace(post.copyWith(likedByMe: liked, likeCount: count));
    } catch (_) {
      replace(post);
      rethrow;
    }
  }

  void replace(ForumPost post) {
    final list = state.valueOrNull;
    if (list != null && mounted) state = AsyncData([for (final p in list) p.id == post.id ? post : p]);
  }

  void prepend(ForumPost post) {
    final list = state.valueOrNull ?? const <ForumPost>[];
    if (mounted) state = AsyncData([post, ...list]);
  }

  void remove(String id) {
    final list = state.valueOrNull;
    if (list != null && mounted) state = AsyncData(list.where((p) => p.id != id).toList());
  }
}

final forumFeedProvider = StateNotifierProvider.autoDispose<ForumFeedNotifier, AsyncValue<List<ForumPost>>>((ref) {
  final scope = ref.watch(forumScopeProvider);
  // Chỉ theo dõi Trường / Cụm của mình: gia hạn token (phiên mới cùng Trường) không tải lại bảng tin.
  // Record so sánh theo giá trị (CampusInfo thì không).
  final (uniId, cluster) = ref.watch(authSessionProvider.select(
    (s) => s is AuthSignedIn ? (s.user.university?.id, s.user.university?.clusterCode) : (null, null),
  ));
  return ForumFeedNotifier(
    ref.watch(forumRepositoryProvider),
    cluster: scope == ForumScope.cluster ? cluster : null,
    universityId: scope == ForumScope.university ? uniId : null,
  );
});

final postCommentsProvider = FutureProvider.autoDispose.family<List<ForumComment>, String>(
  (ref, postId) => ref.watch(forumRepositoryProvider).comments(postId),
);
