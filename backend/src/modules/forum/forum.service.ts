import { randomUUID } from 'crypto';
import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';
import { sniffImageType } from '../profile/profile.service';
import { CreatePostDto, FeedQueryDto, MAX_POST_IMAGE_BYTES, MAX_POST_IMAGES, UpdatePostDto } from './dto/forum.dto';
import { ForumImageStore } from './forum-image.store';

export interface UploadedImage {
  buffer: Buffer;
}

const EXT: Record<string, string> = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };

const notFound = (what: string) => new NotFoundException({ code: 'HTTP_404', message: `Không tìm thấy ${what}.` });
const notOwner = () => new ForbiddenException({ code: 'ERR_117', message: 'Bạn chỉ sửa / xoá được nội dung của chính mình.' });
const emptyPost = () =>
  new BadRequestException({ code: 'ERR_115', message: `Bài đăng cần nội dung hoặc ảnh (tối đa ${MAX_POST_IMAGES} ảnh).` });

/** Một dòng bảng tin: bài + tác giả + Trường + Phiên chạy đính kèm + số tym / bình luận. */
const POST_SELECT = `
  SELECT p.id, p.body, p.image_paths, p.created_at, p.edited_at, p.author_id,
         a.display_name AS author_name, av.updated_at AS avatar_at,
         un.id AS uni_id, COALESCE(un.short_name, un.short_code) AS uni_short, un.hex_color AS uni_color,
         d.cluster_code,
         s.id AS run_id, s.distance_meters, s.duration_seconds, s.created_at AS run_at,
         (SELECT COUNT(*)::int FROM public.forum_likes l WHERE l.post_id = p.id) AS like_count,
         (SELECT COUNT(*)::int FROM public.forum_comments c WHERE c.post_id = p.id) AS comment_count,
         EXISTS (SELECT 1 FROM public.forum_likes l WHERE l.post_id = p.id AND l.user_id = $1) AS liked
  FROM public.forum_posts p
  JOIN public.users a ON a.id = p.author_id
  LEFT JOIN public.user_avatars av ON av.user_id = p.author_id
  LEFT JOIN public.universities un ON un.id = p.university_id
  LEFT JOIN public.districts d ON d.name = un.district
  LEFT JOIN public.running_sessions s ON s.id = p.session_id`;

/** Diễn đàn: bài khoe thành tích (chữ, ảnh, Phiên chạy đính kèm), tym, bình luận, báo cáo. */
@Injectable()
export class ForumService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly images: ForumImageStore,
  ) {}

  async feed(userId: string, q: FeedQueryDto) {
    const rows = await this.dataSource.query(
      `${POST_SELECT}
       WHERE ($2::uuid IS NULL OR p.university_id = $2)
         AND ($3::varchar IS NULL OR d.cluster_code = $3)
         AND ($4::timestamptz IS NULL OR p.created_at < $4)
       ORDER BY p.created_at DESC
       LIMIT $5`,
      [userId, q.universityId ?? null, q.cluster ?? null, q.before ?? null, q.limit],
    );
    return rows.map((r: PostRow) => this.toView(r, userId));
  }

  async getPost(userId: string, postId: string) {
    const [row] = await this.dataSource.query(`${POST_SELECT} WHERE p.id = $2`, [userId, postId]);
    if (!row) throw notFound('bài đăng');
    return this.toView(row, userId);
  }

  async createPost(userId: string, dto: CreatePostDto, files: UploadedImage[] = []) {
    const body = dto.body?.trim() ?? '';
    if (!body && files.length === 0) throw emptyPost();
    if (files.length > MAX_POST_IMAGES) throw emptyPost();
    if (dto.sessionId) await this.assertOwnValidRun(this.dataSource.manager, userId, dto.sessionId);

    const uploaded = await this.uploadAll(userId, files);
    try {
      const [{ id }] = await this.dataSource.query(
        `INSERT INTO public.forum_posts (author_id, university_id, body, image_paths, session_id)
         SELECT u.id, u.university_id, $2, $3::text[], $4 FROM public.users u WHERE u.id = $1
         RETURNING id`,
        [userId, body, uploaded, dto.sessionId ?? null],
      );
      return this.getPost(userId, id);
    } catch (e) {
      await this.images.remove(uploaded); // không để ảnh mồ côi khi ghi DB lỗi
      throw e;
    }
  }

  /** Sửa chữ, ảnh (giữ ảnh cũ theo `keepImages` + thêm ảnh mới), Phiên chạy đính kèm; đánh dấu "đã chỉnh sửa". */
  async updatePost(userId: string, postId: string, dto: UpdatePostDto, files: UploadedImage[] = []) {
    const post = await this.ownPost(userId, postId);
    const keep = dto.keepImages === undefined ? post.image_paths : this.pickKept(post.image_paths, dto.keepImages);
    if (keep.length + files.length > MAX_POST_IMAGES) throw emptyPost();
    const body = dto.body === undefined ? post.body : dto.body.trim();
    if (!body && keep.length + files.length === 0) throw emptyPost();
    if (dto.sessionId) await this.assertOwnValidRun(this.dataSource.manager, userId, dto.sessionId);

    const uploaded = await this.uploadAll(userId, files);
    try {
      await this.dataSource.query(
        `UPDATE public.forum_posts
         SET body = $2, image_paths = $3::text[],
             session_id = CASE WHEN $4::text IS NULL THEN session_id ELSE NULLIF($4, '')::uuid END,
             edited_at = now()
         WHERE id = $1`,
        [postId, body, [...keep, ...uploaded], dto.sessionId ?? null],
      );
    } catch (e) {
      await this.images.remove(uploaded);
      throw e;
    }
    await this.images.remove(post.image_paths.filter((p) => !keep.includes(p)));
    return this.getPost(userId, postId);
  }

  async deletePost(userId: string, postId: string) {
    await this.ownPost(userId, postId);
    const paths = await this.deletePostRow(this.dataSource.manager, postId);
    await this.images.remove(paths);
    return { id: postId };
  }

  /** Xoá bài (tym, bình luận, báo cáo xoá theo); trả đường dẫn ảnh để xoá khỏi Storage sau khi commit. */
  async deletePostRow(m: EntityManager, postId: string): Promise<string[]> {
    const [rows] = await m.query(`DELETE FROM public.forum_posts WHERE id = $1 RETURNING image_paths`, [postId]);
    if (!rows?.length) throw notFound('bài đăng');
    return rows[0].image_paths;
  }

  async like(userId: string, postId: string, liked: boolean) {
    await this.assertPostExists(postId);
    await this.dataSource.query(
      liked
        ? `INSERT INTO public.forum_likes (post_id, user_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`
        : `DELETE FROM public.forum_likes WHERE post_id = $1 AND user_id = $2`,
      [postId, userId],
    );
    const [{ n }] = await this.dataSource.query(`SELECT COUNT(*)::int AS n FROM public.forum_likes WHERE post_id = $1`, [postId]);
    return { liked, likeCount: n };
  }

  async comments(userId: string, postId: string) {
    await this.assertPostExists(postId);
    const rows = await this.dataSource.query(
      `SELECT c.id, c.body, c.created_at, c.edited_at, c.author_id, a.display_name AS author_name, av.updated_at AS avatar_at
       FROM public.forum_comments c
       JOIN public.users a ON a.id = c.author_id
       LEFT JOIN public.user_avatars av ON av.user_id = c.author_id
       WHERE c.post_id = $1 ORDER BY c.created_at`,
      [postId],
    );
    return rows.map((r: CommentRow) => this.toCommentView(r, userId));
  }

  async addComment(userId: string, postId: string, body: string) {
    await this.assertPostExists(postId);
    const [{ id }] = await this.dataSource.query(
      `INSERT INTO public.forum_comments (post_id, author_id, body) VALUES ($1, $2, $3) RETURNING id`,
      [postId, userId, this.commentBody(body)],
    );
    return this.getComment(userId, id);
  }

  async updateComment(userId: string, commentId: string, body: string) {
    await this.ownComment(userId, commentId);
    await this.dataSource.query(`UPDATE public.forum_comments SET body = $2, edited_at = now() WHERE id = $1`, [
      commentId,
      this.commentBody(body),
    ]);
    return this.getComment(userId, commentId);
  }

  async deleteComment(userId: string, commentId: string) {
    await this.ownComment(userId, commentId);
    await this.dataSource.query(`DELETE FROM public.forum_comments WHERE id = $1`, [commentId]);
    return { id: commentId };
  }

  /** Báo cáo bài hoặc bình luận của bài; báo cáo lại cùng mục thì bỏ qua. */
  async report(userId: string, postId: string, commentId: string | undefined, reason: string | undefined) {
    await this.assertPostExists(postId);
    if (commentId) {
      const [c] = await this.dataSource.query(`SELECT 1 FROM public.forum_comments WHERE id = $1 AND post_id = $2`, [commentId, postId]);
      if (!c) throw notFound('bình luận');
    }
    await this.dataSource.query(
      `INSERT INTO public.forum_reports (post_id, comment_id, reporter_id, reason) VALUES ($1, $2, $3, $4)
       ON CONFLICT (post_id, COALESCE(comment_id, '00000000-0000-0000-0000-000000000000'::uuid), reporter_id) DO NOTHING`,
      [postId, commentId ?? null, userId, reason?.trim() || null],
    );
    return { reported: true };
  }

  // ---------- nội bộ ----------

  private commentBody(body: string): string {
    const text = body.trim();
    if (!text) throw new BadRequestException({ code: 'HTTP_400', message: 'Bình luận không được để trống.' });
    return text;
  }

  private async getComment(userId: string, id: string) {
    const [row] = await this.dataSource.query(
      `SELECT c.id, c.body, c.created_at, c.edited_at, c.author_id, a.display_name AS author_name, av.updated_at AS avatar_at
       FROM public.forum_comments c JOIN public.users a ON a.id = c.author_id
       LEFT JOIN public.user_avatars av ON av.user_id = c.author_id WHERE c.id = $1`,
      [id],
    );
    return this.toCommentView(row, userId);
  }

  private async assertPostExists(postId: string) {
    const [p] = await this.dataSource.query(`SELECT 1 FROM public.forum_posts WHERE id = $1`, [postId]);
    if (!p) throw notFound('bài đăng');
  }

  private async ownPost(userId: string, postId: string): Promise<{ author_id: string; body: string; image_paths: string[] }> {
    const [post] = await this.dataSource.query(`SELECT author_id, body, image_paths FROM public.forum_posts WHERE id = $1`, [postId]);
    if (!post) throw notFound('bài đăng');
    if (post.author_id !== userId) throw notOwner();
    return post;
  }

  private async ownComment(userId: string, commentId: string) {
    const [c] = await this.dataSource.query(`SELECT author_id FROM public.forum_comments WHERE id = $1`, [commentId]);
    if (!c) throw notFound('bình luận');
    if (c.author_id !== userId) throw notOwner();
  }

  /** Chỉ đính kèm Phiên chạy đã hoàn thành, hợp lệ, của chính tác giả (số liệu do server kiểm định). */
  private async assertOwnValidRun(m: EntityManager, userId: string, sessionId: string) {
    const [run] = await m.query(
      `SELECT 1 FROM public.running_sessions WHERE id = $1 AND user_id = $2 AND status = 'COMPLETED' AND is_valid`,
      [sessionId, userId],
    );
    if (!run) {
      throw new BadRequestException({ code: 'ERR_116', message: 'Chỉ đính kèm được Phiên chạy hợp lệ của chính bạn.' });
    }
  }

  /** `keepImages` là URL công khai app đang có; chỉ giữ ảnh thật sự thuộc bài, theo thứ tự app gửi. */
  private pickKept(current: string[], keepJson: string): string[] {
    let urls: unknown;
    try {
      urls = JSON.parse(keepJson);
    } catch {
      urls = null;
    }
    if (!Array.isArray(urls)) throw new BadRequestException({ code: 'HTTP_400', message: 'keepImages phải là mảng JSON.' });
    return urls.map((u) => current.find((p) => this.images.publicUrl(p) === u || p === u)).filter((p): p is string => !!p);
  }

  private async uploadAll(userId: string, files: UploadedImage[]): Promise<string[]> {
    const typed = files.map((f) => {
      const mime = f.buffer.length <= MAX_POST_IMAGE_BYTES ? sniffImageType(f.buffer) : null;
      if (!mime) {
        throw new BadRequestException({ code: 'ERR_104', message: 'Ảnh phải là JPEG, PNG hoặc WebP, tối đa 1 MB mỗi ảnh.' });
      }
      return { ...f, mime };
    });
    const done: string[] = [];
    try {
      for (const f of typed) {
        const path = `${userId}/${randomUUID()}.${EXT[f.mime]}`;
        await this.images.upload(path, f.buffer, f.mime);
        done.push(path);
      }
    } catch (e) {
      await this.images.remove(done);
      throw e;
    }
    return done;
  }

  private toView(r: PostRow, userId: string) {
    return {
      id: r.id,
      body: r.body,
      images: r.image_paths.map((p) => this.images.publicUrl(p)),
      author: {
        id: r.author_id,
        displayName: r.author_name ?? '',
        avatarUrl: r.avatar_at ? `/api/v1/profile/avatar/${r.author_id}?v=${new Date(r.avatar_at).getTime()}` : null,
      },
      university: r.uni_id ? { id: r.uni_id, shortName: r.uni_short, color: r.uni_color, clusterCode: r.cluster_code } : null,
      run: r.run_id
        ? { id: r.run_id, distanceKm: Number(r.distance_meters) / 1000, durationSeconds: Number(r.duration_seconds), startedAt: r.run_at }
        : null,
      likeCount: r.like_count,
      commentCount: r.comment_count,
      likedByMe: r.liked,
      mine: r.author_id === userId,
      createdAt: r.created_at,
      editedAt: r.edited_at,
    };
  }

  private toCommentView(r: CommentRow, userId: string) {
    return {
      id: r.id,
      body: r.body,
      author: {
        id: r.author_id,
        displayName: r.author_name ?? '',
        avatarUrl: r.avatar_at ? `/api/v1/profile/avatar/${r.author_id}?v=${new Date(r.avatar_at).getTime()}` : null,
      },
      mine: r.author_id === userId,
      createdAt: r.created_at,
      editedAt: r.edited_at,
    };
  }
}

interface PostRow {
  id: string;
  body: string;
  image_paths: string[];
  created_at: Date;
  edited_at: Date | null;
  author_id: string;
  author_name: string | null;
  avatar_at: Date | null;
  uni_id: string | null;
  uni_short: string | null;
  uni_color: string | null;
  cluster_code: string | null;
  run_id: string | null;
  distance_meters: number | null;
  duration_seconds: number | null;
  run_at: Date | null;
  like_count: number;
  comment_count: number;
  liked: boolean;
}

interface CommentRow {
  id: string;
  body: string;
  created_at: Date;
  edited_at: Date | null;
  author_id: string;
  author_name: string | null;
  avatar_at: Date | null;
}
