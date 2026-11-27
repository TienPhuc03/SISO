import { ConfigService } from '@nestjs/config';
import { DataSource } from 'typeorm';
import { ForumImageStore } from './forum-image.store';
import { ForumService } from './forum.service';

const ME = 'u-me';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]);

/** DataSource giả: trả lời theo câu SQL; `post` là bài đang có trong DB. */
function setup(opts: { post?: { author_id: string; body: string; image_paths: string[] } | null; run?: boolean; insertFails?: boolean } = {}) {
  const post = opts.post === undefined ? { author_id: ME, body: 'cũ', image_paths: ['u-me/a.jpg', 'u-me/b.jpg'] } : opts.post;
  const query = jest.fn(async (sql: string, _params?: unknown[]) => {
    if (sql.includes('FROM public.running_sessions WHERE id')) return opts.run === false ? [] : [{ 1: 1 }];
    if (sql.includes('INSERT INTO public.forum_posts')) {
      if (opts.insertFails) throw new Error('db down');
      return [{ id: 'p-new' }];
    }
    if (sql.includes('SELECT author_id, body, image_paths')) return post ? [post] : [];
    if (sql.includes('DELETE FROM public.forum_posts')) return [post ? [{ image_paths: post.image_paths }] : [], post ? 1 : 0];
    if (sql.includes('SELECT 1 FROM public.forum_posts')) return post ? [{}] : [];
    if (sql.includes('FROM public.forum_comments WHERE id = $1 AND post_id')) return [];
    if (sql.includes('COUNT(*)::int AS n')) return [{ n: 7 }];
    if (sql.includes('FROM public.forum_posts p')) return [row()];
    return [];
  });
  const ds = { query, manager: { query } } as unknown as DataSource;
  const images = {
    enabled: true,
    publicUrl: (p: string) => `https://x.supabase.co/storage/v1/object/public/forum/${p}`,
    upload: jest.fn(async () => undefined),
    remove: jest.fn(async () => undefined),
  };
  return { query, images, service: new ForumService(ds, images as unknown as ForumImageStore) };
}

const row = () => ({
  id: 'p1',
  body: 'Chạy 5 km',
  image_paths: ['u-me/a.jpg'],
  created_at: new Date('2026-11-27T01:00:00Z'),
  edited_at: null,
  author_id: ME,
  author_name: 'Minh',
  avatar_at: null,
  uni_id: 'uni',
  uni_short: 'UEH N',
  uni_color: '#005F69',
  cluster_code: 'SOUTH',
  run_id: 's1',
  distance_meters: 5230,
  duration_seconds: 1800,
  run_at: new Date('2026-11-26T23:00:00Z'),
  like_count: 3,
  comment_count: 1,
  liked: true,
});

const code = (p: Promise<unknown>) => p.then(() => 'ok', (e) => e.response?.code ?? e.message);

describe('ForumService', () => {
  describe('đăng bài', () => {
    it('bài rỗng (không chữ, không ảnh) -> ERR_115', async () => {
      expect(await code(setup().service.createPost(ME, { body: '   ' }, []))).toBe('ERR_115');
    });

    it('quá 4 ảnh -> ERR_115, không upload', async () => {
      const { service, images } = setup();
      expect(await code(service.createPost(ME, {}, Array(5).fill({ buffer: JPEG })))).toBe('ERR_115');
      expect(images.upload).not.toHaveBeenCalled();
    });

    it('file không phải ảnh -> ERR_104, không upload', async () => {
      const { service, images } = setup();
      expect(await code(service.createPost(ME, {}, [{ buffer: Buffer.from('GIF89a') }]))).toBe('ERR_104');
      expect(images.upload).not.toHaveBeenCalled();
    });

    it('đính kèm Phiên chạy không phải của mình / không hợp lệ -> ERR_116', async () => {
      expect(await code(setup({ run: false }).service.createPost(ME, { body: 'x', sessionId: 's9' }))).toBe('ERR_116');
    });

    it('upload ảnh theo thư mục của tác giả, đuôi theo loại thật, rồi ghi bài', async () => {
      const { service, images, query } = setup();
      const view = await service.createPost(ME, { body: ' Chạy 5 km ' }, [{ buffer: JPEG }, { buffer: PNG }]);

      const paths = images.upload.mock.calls.map((c: unknown[]) => c[0] as string);
      expect(paths[0]).toMatch(/^u-me\/[0-9a-f-]{36}\.jpg$/);
      expect(paths[1]).toMatch(/\.png$/);
      const insert = query.mock.calls.find((c) => String(c[0]).includes('INSERT INTO public.forum_posts'))!;
      expect(insert[1]).toEqual([ME, 'Chạy 5 km', paths, null]);
      expect(view).toMatchObject({ id: 'p1', mine: true, likedByMe: true, run: { distanceKm: 5.23, durationSeconds: 1800 } });
      expect(view.images[0]).toBe('https://x.supabase.co/storage/v1/object/public/forum/u-me/a.jpg');
    });

    it('ghi DB lỗi -> xoá ảnh vừa upload', async () => {
      const { service, images } = setup({ insertFails: true });
      await expect(service.createPost(ME, {}, [{ buffer: JPEG }])).rejects.toThrow('db down');
      expect(images.remove).toHaveBeenCalledWith([expect.stringMatching(/^u-me\//)]);
    });
  });

  describe('sửa / xoá bài', () => {
    it('bài của người khác -> ERR_117', async () => {
      const { service } = setup({ post: { author_id: 'other', body: 'x', image_paths: [] } });
      expect(await code(service.updatePost(ME, 'p1', { body: 'y' }))).toBe('ERR_117');
      expect(await code(service.deletePost(ME, 'p1'))).toBe('ERR_117');
    });

    it('giữ ảnh theo URL app gửi (bỏ URL lạ), thêm ảnh mới, xoá ảnh bị bỏ khỏi Storage', async () => {
      const { service, images, query } = setup();
      const keep = JSON.stringify([
        'https://x.supabase.co/storage/v1/object/public/forum/u-me/b.jpg',
        'https://evil.example/x.jpg',
      ]);
      await service.updatePost(ME, 'p1', { keepImages: keep, sessionId: '' }, [{ buffer: JPEG }]);

      const update = query.mock.calls.find((c) => String(c[0]).includes('UPDATE public.forum_posts'))!;
      const saved = (update[1] as unknown[])[2] as string[];
      expect(saved[0]).toBe('u-me/b.jpg');
      expect(saved).toHaveLength(2);
      expect((update[1] as unknown[])[3]).toBe('');
      expect(String(update[0])).toContain('edited_at = now()');
      expect(images.remove).toHaveBeenLastCalledWith(['u-me/a.jpg']);
    });

    it('giữ 2 ảnh + thêm 3 ảnh = 5 -> ERR_115', async () => {
      expect(await code(setup().service.updatePost(ME, 'p1', {}, Array(3).fill({ buffer: JPEG })))).toBe('ERR_115');
    });

    it('xoá bài của mình: xoá dòng rồi xoá ảnh', async () => {
      const { service, images } = setup();
      await service.deletePost(ME, 'p1');
      expect(images.remove).toHaveBeenCalledWith(['u-me/a.jpg', 'u-me/b.jpg']);
    });
  });

  it('tym / bỏ tym trả số tym mới', async () => {
    const { service, query } = setup();
    await expect(service.like(ME, 'p1', true)).resolves.toEqual({ liked: true, likeCount: 7 });
    expect(query.mock.calls.some((c) => String(c[0]).includes('ON CONFLICT DO NOTHING'))).toBe(true);
    await service.like(ME, 'p1', false);
    expect(query.mock.calls.some((c) => String(c[0]).includes('DELETE FROM public.forum_likes'))).toBe(true);
  });

  it('bài không tồn tại: tym / bình luận -> 404', async () => {
    const { service } = setup({ post: null });
    await expect(service.like(ME, 'p1', true)).rejects.toMatchObject({ status: 404 });
    await expect(service.addComment(ME, 'p1', 'hay')).rejects.toMatchObject({ status: 404 });
  });

  it('báo cáo bình luận không thuộc bài -> 404', async () => {
    await expect(setup().service.report(ME, 'p1', 'c-other', 'spam')).rejects.toMatchObject({ status: 404 });
  });
});

describe('ForumImageStore', () => {
  const store = (env: Record<string, string>) => new ForumImageStore({ get: (k: string) => env[k] } as unknown as ConfigService);
  afterEach(() => jest.restoreAllMocks());

  it('thiếu cấu hình: tắt, upload báo ERR_114', async () => {
    const s = store({});
    expect(s.enabled).toBe(false);
    await expect(s.upload('a.jpg', JPEG, 'image/jpeg')).rejects.toMatchObject({ response: { code: 'ERR_114' } });
  });

  it('khoá mới sb_secret: chỉ gửi header apikey (không phải JWT nên không dùng Bearer)', async () => {
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
    const s = store({ SUPABASE_URL: 'https://x.supabase.co/', SUPABASE_SERVICE_ROLE_KEY: 'sb_secret_abc' });
    await s.upload('u/a.jpg', JPEG, 'image/jpeg');

    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe('https://x.supabase.co/storage/v1/object/forum/u/a.jpg');
    const headers = init!.headers as Record<string, string>;
    expect(headers.apikey).toBe('sb_secret_abc');
    expect(headers.Authorization).toBeUndefined();
    expect(s.publicUrl('u/a.jpg')).toBe('https://x.supabase.co/storage/v1/object/public/forum/u/a.jpg');
  });

  it('khoá service_role cũ (JWT): gửi cả apikey và Bearer', async () => {
    const fetchMock = jest.spyOn(global, 'fetch').mockResolvedValue(new Response('{}', { status: 200 }));
    const s = store({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'eyJhbGciOi.x.y' });
    await s.upload('u/a.jpg', JPEG, 'image/jpeg');
    expect((fetchMock.mock.calls[0][1]!.headers as Record<string, string>).Authorization).toBe('Bearer eyJhbGciOi.x.y');
  });

  it('xoá ảnh lỗi: chỉ ghi log, không ném lỗi', async () => {
    jest.spyOn(global, 'fetch').mockRejectedValue(new Error('network'));
    const s = store({ SUPABASE_URL: 'https://x.supabase.co', SUPABASE_SERVICE_ROLE_KEY: 'k' });
    await expect(s.remove(['u/a.jpg'])).resolves.toBeUndefined();
  });
});
