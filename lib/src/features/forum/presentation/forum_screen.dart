import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../leaderboard/presentation/leaderboard_screen.dart';
import '../../map/presentation/siso_bottom_nav.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../tracking/presentation/active_run_screen.dart';
import '../domain/forum_models.dart';
import '../providers/forum_providers.dart';
import 'forum_actions.dart';
import 'post_card.dart';
import 'post_detail_screen.dart';
import 'post_editor_screen.dart';

/// Diễn đàn: bảng tin khoe thành tích, lọc theo Cụm / Trường của mình, đăng bài, tym, bình luận.
class ForumScreen extends ConsumerWidget {
  const ForumScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(forumFeedProvider);
    final scope = ref.watch(forumScopeProvider);
    final session = ref.watch(authSessionProvider);
    final hasSchool = session is AuthSignedIn && session.user.university != null;

    Future<void> openEditor([ForumPost? post]) async {
      final saved =
          await Navigator.of(context).push<ForumPost>(MaterialPageRoute(builder: (_) => PostEditorScreen(post: post)));
      if (saved == null) return;
      final notifier = ref.read(forumFeedProvider.notifier);
      post == null ? notifier.prepend(saved) : notifier.replace(saved);
    }

    return Scaffold(
      backgroundColor: SisoColors.bg,
      floatingActionButton: hasSchool
          ? Padding(
              padding: const EdgeInsets.only(bottom: 96),
              child: FloatingActionButton.extended(
                key: const Key('forum_new_post'),
                onPressed: openEditor,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Đăng bài'),
              ),
            )
          : null,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () => ref.read(forumFeedProvider.notifier).refresh(),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 160),
                children: [
                  const Text('Diễn đàn', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                  const Text('Khoe thành tích, cổ vũ đồng đội', style: TextStyle(fontSize: 14, color: SisoColors.body)),
                  if (hasSchool) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final (s, label) in const [
                          (ForumScope.all, 'Tất cả'),
                          (ForumScope.cluster, 'Cụm của tôi'),
                          (ForumScope.university, 'Trường của tôi'),
                        ])
                          ChoiceChip(
                            key: Key('forum_scope_${s.name}'),
                            label: Text(label),
                            selected: scope == s,
                            onSelected: (_) => ref.read(forumScopeProvider.notifier).state = s,
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  ...feed.when(
                    loading: () =>
                        const [Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))],
                    error: (_, __) => [
                      const Text('Không tải được bảng tin.', key: Key('forum_error')),
                      TextButton(onPressed: () => ref.invalidate(forumFeedProvider), child: const Text('Thử lại')),
                    ],
                    data: (posts) => posts.isEmpty
                        ? const [
                            Padding(
                              padding: EdgeInsets.symmetric(vertical: 32),
                              child: Text('Chưa có bài nào. Hãy là người đầu tiên khoe thành tích!',
                                  textAlign: TextAlign.center, style: TextStyle(color: SisoColors.body)),
                            ),
                          ]
                        : [
                            for (final p in posts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: PostCard(
                                  post: p,
                                  canInteract: hasSchool,
                                  onLike: () =>
                                      ref.read(forumFeedProvider.notifier).toggleLike(p).catchError((Object e) {
                                    if (context.mounted) showForumError(context, e);
                                  }),
                                  onOpen: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(builder: (_) => PostDetailScreen(postId: p.id)),
                                  ),
                                  onAction: (a) => handlePostAction(context, ref, p, a, onEdit: () => openEditor(p)),
                                ),
                              ),
                            if (ref.read(forumFeedProvider.notifier).hasMore)
                              Center(
                                child: TextButton(
                                  key: const Key('forum_load_more'),
                                  onPressed: () =>
                                      ref.read(forumFeedProvider.notifier).loadMore().catchError((Object e) {
                                    if (context.mounted) showForumError(context, e);
                                  }),
                                  child: const Text('Tải thêm'),
                                ),
                              ),
                          ],
                  ),
                ],
              ),
            ),
          ),
          if (hasSchool || (session is AuthSignedIn && session.user.isAdmin))
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SisoBottomNav(
                active: SisoTab.forum,
                onMap: () => Navigator.of(context).maybePop(),
                onRun: () => Navigator.of(context)
                    .pushReplacement(MaterialPageRoute<void>(builder: (_) => const ActiveRunScreen())),
                onLeaderboard: () => Navigator.of(context)
                    .pushReplacement(MaterialPageRoute<void>(builder: (_) => const LeaderboardScreen())),
                onForum: () {},
                onProfile: () => Navigator.of(context)
                    .pushReplacement(MaterialPageRoute<void>(builder: (_) => const ProfileScreen())),
              ),
            ),
        ],
      ),
    );
  }
}

/// Sửa / xoá bài của mình, báo cáo bài người khác. Dùng chung cho bảng tin và màn chi tiết.
Future<void> handlePostAction(
  BuildContext context,
  WidgetRef ref,
  ForumPost post,
  PostAction action, {
  required VoidCallback onEdit,
  VoidCallback? onDeleted,
}) async {
  final repo = ref.read(forumRepositoryProvider);
  try {
    switch (action) {
      case PostAction.edit:
        onEdit();
      case PostAction.delete:
        if (!await confirmForumDelete(context, 'bài')) return;
        await repo.deletePost(post.id);
        ref.read(forumFeedProvider.notifier).remove(post.id);
        onDeleted?.call();
      case PostAction.report:
        final reason = await askReportReason(context, 'bài');
        if (reason == null) return;
        await repo.report(post.id, reason: reason);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi báo cáo cho admin.')));
        }
    }
  } catch (e) {
    if (context.mounted) showForumError(context, e);
  }
}
