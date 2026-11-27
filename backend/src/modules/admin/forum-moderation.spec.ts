import { DataSource } from 'typeorm';
import { ForumImageStore } from '../forum/forum-image.store';
import { ForumService } from '../forum/forum.service';
import { AdminAuditService } from './admin-audit.service';
import { ForumModerationService } from './forum-moderation.service';

const ADMIN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function setup(opts: { post?: boolean; dismissed?: number; comment?: boolean } = {}) {
  const tx = {
    query: jest.fn(async (sql: string) => {
      if (sql.includes('SELECT author_id, body FROM public.forum_posts')) return opts.post === false ? [] : [{ author_id: 'u2', body: 'x'.repeat(300) }];
      if (sql.includes('UPDATE public.forum_reports')) return [[], opts.dismissed ?? 1];
      if (sql.includes('DELETE FROM public.forum_comments')) return [opts.comment === false ? [] : [{ author_id: 'u2', post_id: 'p1', body: 'tệ' }], 1];
      if (sql.includes('INSERT INTO public.admin_actions')) return [];
      return [];
    }),
  };
  const ds = { transaction: jest.fn((fn) => fn(tx)), query: tx.query } as unknown as DataSource;
  const forum = { deletePostRow: jest.fn(async () => ['u2/a.jpg']) };
  const images = { remove: jest.fn(async () => undefined), publicUrl: (p: string) => `https://x/${p}` };
  const audit = { log: jest.fn(async () => undefined) };
  const service = new ForumModerationService(
    ds,
    forum as unknown as ForumService,
    images as unknown as ForumImageStore,
    audit as unknown as AdminAuditService,
  );
  return { tx, forum, images, audit, service };
}

describe('ForumModerationService', () => {
  it('xoá bài: xoá dòng trong transaction có ghi nhật ký, rồi xoá ảnh khỏi Storage', async () => {
    const { service, forum, images, audit } = setup();
    await service.deletePost(ADMIN, 'p1');
    expect(forum.deletePostRow).toHaveBeenCalledWith(expect.anything(), 'p1');
    expect(audit.log).toHaveBeenCalledWith(expect.anything(), ADMIN, 'forum.post.delete', 'forum_post', 'p1', {
      authorId: 'u2',
      body: 'x'.repeat(200),
      images: 1,
    });
    expect(images.remove).toHaveBeenCalledWith(['u2/a.jpg']);
  });

  it('bài không tồn tại -> 404, không xoá ảnh', async () => {
    const { service, images } = setup({ post: false });
    await expect(service.deletePost(ADMIN, 'p1')).rejects.toMatchObject({ status: 404 });
    expect(images.remove).not.toHaveBeenCalled();
  });

  it('xoá bình luận: ghi nhật ký kèm bài và tác giả', async () => {
    const { service, audit } = setup();
    await service.deleteComment(ADMIN, 'c1');
    expect(audit.log).toHaveBeenCalledWith(expect.anything(), ADMIN, 'forum.comment.delete', 'forum_comment', 'c1', {
      authorId: 'u2',
      postId: 'p1',
      body: 'tệ',
    });
  });

  it('bỏ qua báo cáo đã xử lý / không tồn tại -> 404', async () => {
    await expect(setup({ dismissed: 0 }).service.dismissReport(ADMIN, 'r1')).rejects.toMatchObject({ status: 404 });
  });
});
