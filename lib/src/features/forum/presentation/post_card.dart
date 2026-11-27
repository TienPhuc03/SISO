import 'package:flutter/material.dart';

import '../../../core/theme/siso_theme.dart';
import '../../map/domain/hex_cell.dart' show parseHexColor;
import '../../profile/presentation/avatar_view.dart';
import '../../tracking/presentation/active_run_screen.dart' show formatDuration, formatPace;
import '../domain/forum_models.dart';

enum PostAction { edit, delete, report }

/// Một bài trên bảng tin: tác giả, Trường, chữ, ảnh, Phiên chạy đã xác thực, tym và bình luận.
class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.onLike,
    required this.onAction,
    this.onOpen,
    this.canInteract = true,
  });

  final ForumPost post;
  final VoidCallback onLike;
  final ValueChanged<PostAction> onAction;

  /// Mở chi tiết (bình luận); null khi đang ở màn chi tiết.
  final VoidCallback? onOpen;

  /// false khi chưa chọn Trường: chỉ xem, không tym / bình luận.
  final bool canInteract;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: Key('post_${post.id}'),
      decoration: sisoCard(radius: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AvatarView(url: post.author.avatarUrl, name: post.author.displayName, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(post.author.displayName,
                        overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Row(
                      children: [
                        if (post.universityShortName case final uni?) ...[
                          CampusDot(color: parseHexColor(post.universityColor), size: 8),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('$uni · ',
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: SisoColors.body)),
                          ),
                        ],
                        Text(
                          timeAgo(post.createdAt, DateTime.now()) + (post.editedAt != null ? ' · đã chỉnh sửa' : ''),
                          style: const TextStyle(fontSize: 12, color: SisoColors.caption),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<PostAction>(
                key: Key('post_menu_${post.id}'),
                tooltip: 'Tuỳ chọn',
                onSelected: onAction,
                itemBuilder: (_) => post.mine
                    ? const [
                        PopupMenuItem(value: PostAction.edit, child: Text('Sửa bài')),
                        PopupMenuItem(value: PostAction.delete, child: Text('Xoá bài')),
                      ]
                    : const [PopupMenuItem(value: PostAction.report, child: Text('Báo cáo bài'))],
              ),
            ],
          ),
          if (post.body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(post.body, style: const TextStyle(fontSize: 14.5, height: 1.4)),
            ),
          ],
          if (post.run case final run?) ...[
            const SizedBox(height: 10),
            _RunBadge(run: run),
          ],
          if (post.images.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.only(right: 8), child: PostImages(urls: post.images)),
          ],
          Row(
            children: [
              TextButton.icon(
                key: Key('post_like_${post.id}'),
                onPressed: canInteract ? onLike : null,
                icon: Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border,
                    color: post.likedByMe ? SisoColors.danger : SisoColors.body, size: 20),
                label: Text('${post.likeCount}', style: const TextStyle(color: SisoColors.body)),
              ),
              TextButton.icon(
                key: Key('post_comments_${post.id}'),
                onPressed: onOpen,
                icon: const Icon(Icons.chat_bubble_outline, color: SisoColors.body, size: 19),
                label: Text('${post.commentCount}', style: const TextStyle(color: SisoColors.body)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Thành tích chạy đính kèm: quãng đường, thời gian, pace (server đã kiểm định).
class _RunBadge extends StatelessWidget {
  const _RunBadge({required this.run});

  final ForumRun run;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: SisoColors.tint, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.directions_run, color: SisoColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${viDecimal(run.distanceKm, 2)} km · ${formatDuration(run.durationSeconds)} · ${formatPace(run.speedKmh)}/km',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          const Tooltip(
            message: 'Số liệu do máy chủ kiểm định',
            child: Icon(Icons.verified, size: 18, color: SisoColors.primary),
          ),
        ],
      ),
    );
  }
}

/// 1 ảnh: rộng hết khung; 2–4 ảnh: lưới 2 cột. Chạm để xem to.
class PostImages extends StatelessWidget {
  const PostImages({super.key, required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    Widget tile(String url) => GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              semanticLabel: 'Ảnh trong bài',
              errorBuilder: (_, __, ___) => Container(
                color: SisoColors.track,
                alignment: Alignment.center,
                child: const Icon(Icons.broken_image_outlined, color: SisoColors.caption),
              ),
            ),
          ),
        );

    if (urls.length == 1) return AspectRatio(aspectRatio: 4 / 3, child: tile(urls.first));
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [for (final u in urls) tile(u)],
    );
  }
}
