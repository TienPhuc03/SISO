import { DataSource, EntityManager } from 'typeorm';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { AuthService } from '../auth/auth.service';
import { foldVietnamese } from './fold-vietnamese';
import { newShortCode, pickColor, UniversitiesService } from './universities.service';
import { universityChoice } from './university-lock';

const SEASON = { season_number: 3, start_date: '2026-11-12' };

/** EntityManager giả: Mùa giải mở, đã chạy chưa, danh sách quận và Trường. */
function fakeManager(opts: { season?: object | null; ran?: boolean; unis?: Partial<University>[] } = {}) {
  const unis = opts.unis ?? [{ id: 'ueh-a', name: 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở A', short_name: 'UEH Cơ sở A', district: 'Quận 3' }];
  return {
    query: jest.fn(async (sql: string, params?: unknown[]) => {
      if (sql.includes('FROM public.seasons')) return opts.season === null ? [] : [opts.season ?? SEASON];
      if (sql.includes('running_sessions')) return [{ ran: opts.ran ?? false }];
      if (sql.includes('FROM public.districts')) return ['Quận 3', 'Bình Chánh'].includes(params![0] as string) ? [{ name: params![0] }] : [];
      return [];
    }),
    findOne: jest.fn(),
    exists: jest.fn(async (_e, { where }) => unis.some((u) => u.id === where.id)),
    find: jest.fn(async () => unis),
    insert: jest.fn(async () => ({ identifiers: [{ id: 'new-uni' }] })),
    update: jest.fn(),
  };
}

describe('foldVietnamese', () => {
  it('bỏ dấu, chữ thường, gộp khoảng trắng; đ -> d', () => {
    expect(foldVietnamese('  Đại Học   Kinh tế TP.HCM ')).toBe('dai hoc kinh te tp.hcm');
    expect(foldVietnamese('Tôn Đức Thắng')).toBe('ton duc thang');
  });
});

describe('Trường tự thêm', () => {
  it('mã nội bộ không dấu, viết hoa, có hậu tố ngẫu nhiên, tối đa 20 ký tự', () => {
    expect(newShortCode('UEH Cơ sở Vĩnh Long dài')).toMatch(/^UEHCOSOVINHL-[0-9A-F]{4}$/);
    expect(newShortCode('---')).toMatch(/^TRUONG-[0-9A-F]{4}$/);
  });

  it('màu tự động cố định theo tên', () => {
    expect(pickColor('ĐH ABC')).toBe(pickColor('dh abc'));
    expect(pickColor('ĐH ABC')).toMatch(/^#[0-9A-F]{6}$/);
  });
});

describe('universityChoice (luật khoá Trường theo Mùa)', () => {
  const run = (user: Partial<User>, opts?: Parameters<typeof fakeManager>[0]) =>
    universityChoice(fakeManager(opts) as unknown as EntityManager, { id: 'u1', ...user } as User);

  it('chưa có Trường: chọn được ngay', async () => {
    await expect(run({ university_id: null as unknown as string })).resolves.toEqual({ season: 3, lockedReason: null });
  });

  it('đã chọn trong Mùa hiện tại: khoá đến Mùa sau', async () => {
    const r = await run({ university_id: 'x', university_season: 3 });
    expect(r.lockedReason).toContain('đổi được khi Mùa 4 bắt đầu');
  });

  it('chọn ở Mùa trước, chưa chạy Mùa này: đổi được', async () => {
    await expect(run({ university_id: 'x', university_season: 2 })).resolves.toEqual({ season: 3, lockedReason: null });
  });

  it('chọn ở Mùa trước nhưng đã có Phiên chạy hợp lệ trong Mùa này: khoá', async () => {
    const r = await run({ university_id: 'x', university_season: null }, { ran: true });
    expect(r.lockedReason).toContain('đã chạy cho Trường hiện tại trong Mùa 3');
  });

  it('không có Mùa giải mở: đổi tự do', async () => {
    await expect(run({ university_id: 'x', university_season: 3 }, { season: null })).resolves.toEqual({
      season: null,
      lockedReason: null,
    });
  });
});

describe('UniversitiesService.choose', () => {
  let tx: ReturnType<typeof fakeManager>;
  let auth: { issueSession: jest.Mock };
  let service: UniversitiesService;
  const setUser = (u: Partial<User>) => tx.findOne.mockResolvedValue({ id: 'u1', ...u });

  beforeEach(() => {
    tx = fakeManager();
    auth = { issueSession: jest.fn(async (id: string) => ({ success: true, data: { userId: id } })) };
    const ds = { transaction: jest.fn((work) => work(tx)) };
    service = new UniversitiesService(ds as unknown as DataSource, auth as unknown as AuthService);
  });

  it('tài khoản mới chọn Trường có sẵn: gán Trường và khoá theo Mùa hiện tại, trả phiên mới', async () => {
    setUser({ university_id: null as unknown as string });
    const res = await service.choose('u1', { universityId: 'ueh-a' });

    expect(tx.update).toHaveBeenCalledWith(User, 'u1', { university_id: 'ueh-a', university_season: 3 });
    expect(auth.issueSession).toHaveBeenCalledWith('u1');
    expect(res).toMatchObject({ data: { userId: 'u1' } });
  });

  it('đang khoá: 403 ERR_112, không đổi gì', async () => {
    setUser({ university_id: 'old', university_season: 3 });
    await expect(service.choose('u1', { universityId: 'ueh-a' })).rejects.toMatchObject({ response: { code: 'ERR_112' } });
    expect(tx.update).not.toHaveBeenCalled();
  });

  it('chọn lại đúng Trường đang có ("Ở lại"): không cập nhật, không khoá thêm', async () => {
    setUser({ university_id: 'ueh-a', university_season: 3 });
    await service.choose('u1', { universityId: 'ueh-a' });
    expect(tx.update).not.toHaveBeenCalled();
  });

  it('Trường không tồn tại: 404', async () => {
    setUser({ university_id: null as unknown as string });
    await expect(service.choose('u1', { universityId: 'ghost' })).rejects.toMatchObject({ status: 404 });
  });

  it('thêm Trường mới: tạo ngay, chờ duyệt, gán cho Sinh viên', async () => {
    setUser({ university_id: null as unknown as string });
    await service.choose('u1', { name: 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở N', shortName: 'UEH N', district: 'Bình Chánh' });

    expect(tx.insert).toHaveBeenCalledWith(
      University,
      expect.objectContaining({
        name: 'ĐH Kinh tế TP.HCM (UEH) - Cơ sở N',
        short_name: 'UEH N',
        district: 'Bình Chánh',
        is_verified: false,
        created_by: 'u1',
      }),
    );
    expect(tx.update).toHaveBeenCalledWith(User, 'u1', { university_id: 'new-uni', university_season: 3 });
  });

  it('tên mới trùng Trường có sẵn (khác dấu / hoa thường): dùng Trường có sẵn, không tạo bản sao', async () => {
    setUser({ university_id: null as unknown as string });
    await service.choose('u1', { name: 'dh kinh te tp.hcm (ueh) - co so a', shortName: 'X', district: 'Quận 3' });

    expect(tx.insert).not.toHaveBeenCalled();
    expect(tx.update).toHaveBeenCalledWith(User, 'u1', { university_id: 'ueh-a', university_season: 3 });
  });

  it('cùng tên viết tắt và cùng quận: coi là trùng', async () => {
    setUser({ university_id: null as unknown as string });
    await service.choose('u1', { name: 'Tên khác hẳn', shortName: 'ueh co so a', district: 'Quận 3' });
    expect(tx.insert).not.toHaveBeenCalled();
  });

  it('quận không có trong danh sách: 400 ERR_113', async () => {
    setUser({ university_id: null as unknown as string });
    await expect(service.choose('u1', { name: 'ĐH Mới', shortName: 'DHM', district: 'Quận 99' })).rejects.toMatchObject({
      response: { code: 'ERR_113' },
    });
    expect(tx.insert).not.toHaveBeenCalled();
  });
});
