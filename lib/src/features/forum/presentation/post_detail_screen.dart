import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/siso_theme.dart';
import '../../auth/providers/auth_provider.dart';
import '../../profile/presentation/avatar_view.dart';
import '../domain/forum_models.dart';
import '../providers/forum_providers.dart';
import 'forum_actions.dart';
import 'forum_screen.dart' show handlePostAction;
import 'post_card.dart';
import 'post_editor_screen.dart';

/// Chi tiết bài: bài đăng + bình luận (một tầng) + ô viết bình luận.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId});

  final String postId;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _comment = TextEditingController();
  ForumPost? _post;
  Object? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await ref.read(forumRepositoryProvider).getPost(widget.postId);
      if (mounted) setState(() => (_post = p, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Cập nhật bài ở đây và trên bảng tin (nếu bảng tin đang mở).
  void _update(ForumPost p) {
    setState(() => _post = p);
    ref.read(forumFeedProvider.notifier).replace(p);
  }

  Future<void> _toggleLike() async {
    final p = _post!;
    final liked = !p.likedByMe;
    _update(p.copyWith(likedByMe: liked, likeCount: p.likeCount + (liked ? 1 : -1)));
    try {
      final count = await ref.read(forumRepositoryProvider).setLiked(p.id, liked);
      if (mounted) _update(p.copyWith(likedByMe: liked, likeCount: count));
    } catch (e) {
      if (!mounted) return;
      _update(p);
      showForumError(context, e);
    }
  }

  Future<void> _send() async {
    final text = _comment.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(forumRepositoryProvider).addComment(widget.postId, text);
      _comment.clear();
      ref.invalidate(postCommentsProvider(widget.postId));
      if (_post case final p?) _update(p.copyWith(commentCount: p.commentCount + 1));
    } catch (e) {
      if (mounted) showForumError(context, e);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _commentAction(ForumComment c, PostAction action) async {
    final repo = ref.read(forumRepositoryProvider);
    try {
      switch (action) {
        case PostAction.edit:
          final text = await editCommentDialog(context, c.body);
          if (text == null || text.isEmpty || text == c.body) return;
          await repo.updateComment(c.id, text);
        case PostAction.delete:
          if (!await confirmForumDelete(context, 'bình luận')) return;
          await repo.deleteComment(c.id);
          if (_post case final p?) _update(p.copyWith(commentCount: p.commentCount - 1));
        case PostAction.report:
          final reason = await askReportReason(context, 'bình luận');
          if (reason == null) return;
          await repo.report(widget.postId, commentId: c.id, reason: reason);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi báo cáo cho admin.')));
          }
          return;
      }
      ref.invalidate(postCommentsProvider(widget.postId));
    } catch (e) {
      if (mounted) showForumError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authSessionProvider);
    final hasSchool = session is AuthSignedIn && session.user.university != null;
    final post = _post;
    final comments = ref.watch(postCommentsProvider(widget.postId));

    return Scaffold(
      appBar: AppBar(title: const Text('Bài đăng')),
      body: post == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Không tải được bài (có thể đã bị xoá).', key: Key('post_error')),
                        TextButton(onPressed: _load, child: const Text('Thử lại')),
                      ],
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      PostCard(
                        post: post,
                        canInteract: hasSchool,
                        onLike: _toggleLike,
                        onAction: (a) => handlePostAction(
                          context,
                          ref,
                          post,
                          a,
                          onEdit: () async {
                            final saved = await Navigator.of(context)
                                .push<ForumPost>(MaterialPageRoute(builder: (_) => PostEditorScreen(post: post)));
                            if (saved != null && mounted) _update(saved);
                          },
                          onDeleted: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Bình luận', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ...comments.when(
                        loading: () => const [
                          Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
                        ],
                        error: (_, __) => [
                          TextButton(
                            onPressed: () => ref.invalidate(postCommentsProvider(widget.postId)),
                            child: const Text('Không tải được bình luận. Thử lại'),
                          ),
                        ],
                        data: (list) => list.isEmpty
                            ? const [
                                Padding(
                                  padding: EdgeInsets.symmetric(vertical: 12),
                                  child: Text('Chưa có bình luận.', style: TextStyle(color: SisoColors.body)),
                                ),
                              ]
                            : [for (final c in list) _CommentTile(comment: c, onAction: (a) => _commentAction(c, a))],
                      ),
                    ],
                  ),
                ),
                if (hasSchool)
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              key: const Key('comment_input'),
                              controller: _comment,
                              maxLength: 1000,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _send(),
                              decoration: const InputDecoration(hintText: 'Viết bình luận…', counterText: ''),
                            ),
                          ),
                          IconButton(
                            key: const Key('comment_send'),
                            tooltip: 'Gửi',
                            onPressed: _sending ? null : _send,
                            icon: const Icon(Icons.send, color: SisoColors.primary),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment, required this.onAction});

  final ForumComment comment;
  final ValueChanged<PostAction> onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: Key('comment_${comment.id}'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AvatarView(url: comment.author.avatarUrl, name: comment.author.displayName, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: comment.author.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                    children: [
                      TextSpan(
                        text:
                            '  ${timeAgo(comment.createdAt, DateTime.now())}${comment.editedAt != null ? ' · đã sửa' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.w400, fontSize: 12, color: SisoColors.caption),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(comment.body),
              ],
            ),
          ),
          PopupMenuButton<PostAction>(
            key: Key('comment_menu_${comment.id}'),
            tooltip: 'Tuỳ chọn',
            onSelected: onAction,
            itemBuilder: (_) => comment.mine
                ? const [
                    PopupMenuItem(value: PostAction.edit, child: Text('Sửa')),
                    PopupMenuItem(value: PostAction.delete, child: Text('Xoá')),
                  ]
                : const [PopupMenuItem(value: PostAction.report, child: Text('Báo cáo'))],
          ),
        ],
      ),
    );
  }
}
