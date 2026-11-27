import { Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { ForumImageStore } from '../forum/forum-image.store';
import { ForumService } from '../forum/forum.service';
import { AdminAuditService } from './admin-audit.service';

const notFound = (what: string) => new NotFoundException({ code: 'HTTP_404', message: `Không tìm thấy ${what}.` });

/** Admin xử lý báo cáo diễn đàn: xem, bỏ qua, xoá bài / bình luận. Mọi thao tác ghi admin_actions. */
@Injectable()
export class ForumModerationService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly forum: ForumService,
    private readonly images: ForumImageStore,
    private readonly audit: AdminAuditService,
  ) {}

  /** Báo cáo (mới nhất trước) kèm nội dung bị báo cáo và người báo cáo. */
  async reports(status: 'open' | 'all') {
    const rows = await this.dataSource.query(
      `SELECT r.id, r.reason, r.created_at AS "createdAt", r.resolved_at AS "resolvedAt",
              rep.email AS "reporterEmail",
              p.id AS "postId", p.body AS "postBody", p.image_paths AS "postImages", pa.email AS "postAuthorEmail",
              c.id AS "commentId", c.body AS "commentBody", ca.email AS "commentAuthorEmail",
              (SELECT COUNT(*)::int FROM public.forum_reports x
               WHERE x.post_id = r.post_id AND x.comment_id IS NOT DISTINCT FROM r.comment_id) AS "reportCount"
       FROM public.forum_reports r
       JOIN public.users rep ON rep.id = r.reporter_id
       JOIN public.forum_posts p ON p.id = r.post_id
       JOIN public.users pa ON pa.id = p.author_id
       LEFT JOIN public.forum_comments c ON c.id = r.comment_id
       LEFT JOIN public.users ca ON ca.id = c.author_id
       WHERE $1 = 'all' OR r.resolved_at IS NULL
       ORDER BY r.created_at DESC
       LIMIT 200`,
      [status],
    );
    return rows.map((r: { postImages: string[] }) => ({ ...r, postImages: r.postImages.map((p) => this.images.publicUrl(p)) }));
  }

  dismissReport(adminId: string, id: string) {
    return this.dataSource.transaction(async (tx) => {
      const [, n] = await tx.query(`UPDATE public.forum_reports SET resolved_at = now() WHERE id = $1 AND resolved_at IS NULL`, [id]);
      if (!n) throw notFound('báo cáo đang mở');
      await this.audit.log(tx, adminId, 'forum.report.dismiss', 'forum_report', id, {});
      return { id };
    });
  }

  async deletePost(adminId: string, postId: string) {
    const paths = await this.dataSource.transaction(async (tx) => {
      const [post] = await tx.query(`SELECT author_id, body FROM public.forum_posts WHERE id = $1`, [postId]);
      if (!post) throw notFound('bài đăng');
      const removed = await this.forum.deletePostRow(tx, postId);
      await this.audit.log(tx, adminId, 'forum.post.delete', 'forum_post', postId, {
        authorId: post.author_id,
        body: String(post.body).slice(0, 200),
        images: removed.length,
      });
      return removed;
    });
    await this.images.remove(paths);
    return { id: postId };
  }

  deleteComment(adminId: string, commentId: string) {
    return this.dataSource.transaction(async (tx) => {
      const [rows] = await tx.query(`DELETE FROM public.forum_comments WHERE id = $1 RETURNING author_id, post_id, body`, [commentId]);
      if (!rows?.length) throw notFound('bình luận');
      const c = rows[0];
      await this.audit.log(tx, adminId, 'forum.comment.delete', 'forum_comment', commentId, {
        authorId: c.author_id,
        postId: c.post_id,
        body: String(c.body).slice(0, 200),
      });
      return { id: commentId };
    });
  }
}
