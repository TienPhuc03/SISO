import { ConflictException, BadRequestException, NotFoundException } from '@nestjs/common';
import { DataSource, QueryFailedError } from 'typeorm';
import { AdminAuditService } from './admin-audit.service';
import { CatalogService } from './catalog.service';
import { StatsService } from './stats.service';
import { StudentsService, likePattern } from './students.service';
import { HallOfFame } from '../../entities/hall-of-fame.entity';
import { Season } from '../../entities/season.entity';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

const ADMIN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

function setup(opts: { findOne?: Map<unknown, unknown>; exists?: Map<unknown, boolean>; query?: jest.Mock } = {}) {
  const tx = {
    findOne: jest.fn(async (e: unknown) => opts.findOne?.get(e) ?? null),
    exists: jest.fn(async (e: unknown) => opts.exists?.get(e) ?? false),
    update: jest.fn(async () => ({ affected: 1 })),
    insert: jest.fn(async () => ({ identifiers: [{ id: 'new-id' }] })),
    delete: jest.fn(async () => ({ affected: 1 })),
    query: opts.query ?? jest.fn(async () => [{ next: 4 }]),
  };
  const ds = { transaction: jest.fn((fn) => fn(tx)), query: jest.fn(async () => [{ total: 0 }]) } as unknown as DataSource;
  const audit = new AdminAuditService(ds);
  return { tx, ds, catalog: new CatalogService(ds, audit), students: new StudentsService(ds, audit), stats: new StatsService(ds) };
}

describe('likePattern', () => {
  it('thoát ký tự đại diện của ILIKE do người dùng gõ', () => {
    expect(likePattern(' 50%_off\\ ')).toBe('%50\\%\\_off\\\\%');
  });
});

describe('StatsService', () => {
  it('Phiên bị kẹt = vẫn ACTIVE, chưa có finished_at, quá 2 giờ (bỏ dòng COMPLETED cũ thiếu finished_at)', async () => {
    const { ds, stats } = setup();
    await stats.stuckSessions();
    const sql = (ds.query as jest.Mock).mock.calls[0][0] as string;
    expect(sql).toContain(`s.status = 'ACTIVE' AND s.finished_at IS NULL AND s.created_at < now() - interval '2 hours'`);
  });

  it('theo giờ / theo ngày: gom theo giờ VN, đủ dòng nhờ generate_series, số ngày truyền bằng tham số', async () => {
    const { ds, stats } = setup();
    await stats.byHour(7);
    await stats.daily(30);
    const [hourSql, hourParams] = (ds.query as jest.Mock).mock.calls[0];
    const [daySql, dayParams] = (ds.query as jest.Mock).mock.calls[1];
    expect(hourSql).toContain('generate_series(0, 23)');
    expect(hourSql).toContain(`AT TIME ZONE 'Asia/Ho_Chi_Minh'`);
    expect(hourParams).toEqual([7]);
    expect(daySql).toMatch(/generate_series\(.*interval '1 day'\)/);
    expect(dayParams).toEqual([30]);
  });
});

describe('StudentsService.list', () => {
  it('tìm theo email/tên + Trường + đang khoá: tham số hoá, phân trang sau tham số lọc', async () => {
    const { ds, students } = setup();
    (ds.query as jest.Mock).mockResolvedValueOnce([]).mockResolvedValueOnce([{ total: 0 }]);
    await students.list({ q: 'an%', universityId: 'u-1', status: 'banned', page: 2, limit: 10 });
    const [sql, params] = (ds.query as jest.Mock).mock.calls[0];
    expect(sql).toContain('(u.email ILIKE $1 OR u.display_name ILIKE $1) AND u.university_id = $2 AND u.banned_until > now()');
    expect(sql).toContain('LIMIT $3 OFFSET $4');
    expect(params).toEqual(['%an\\%%', 'u-1', 10, 10]);
  });

  it('chi tiết Sinh viên không tồn tại -> 404', async () => {
    const { ds, students } = setup();
    (ds.query as jest.Mock).mockResolvedValueOnce([]);
    await expect(students.detail('x')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('CatalogService: Mùa giải', () => {
  it('tạo Mùa giải mở: số = lớn nhất + 1, đóng cờ các Mùa giải khác, ghi nhật ký', async () => {
    const { tx, catalog } = setup();
    const res = await catalog.createSeason(ADMIN, { startDate: '2026-12-01', endDate: '2026-12-31', isActive: true });
    expect(res).toEqual({ seasonNumber: 4 });
    expect(tx.update).toHaveBeenCalledWith(Season, { is_active: true }, { is_active: false });
    expect(tx.insert).toHaveBeenCalledWith(Season, expect.objectContaining({ season_number: 4, is_active: true }));
    expect(tx.insert).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ action: 'season.create' }));
  });

  it('ngày bắt đầu sau ngày kết thúc -> 400', () => {
    expect(() => setup().catalog.createSeason(ADMIN, { startDate: '2026-12-31', endDate: '2026-12-01' })).toThrow(BadRequestException);
  });

  it('không xoá Mùa giải đang mở hoặc đã có Quán quân', async () => {
    const active = setup({ findOne: new Map([[Season, { season_number: 3, is_active: true }]]) });
    await expect(active.catalog.deleteSeason(ADMIN, 3)).rejects.toBeInstanceOf(ConflictException);
    const crowned = setup({
      findOne: new Map([[Season, { season_number: 1, is_active: false }]]),
      exists: new Map([[HallOfFame, true]]),
    });
    await expect(crowned.catalog.deleteSeason(ADMIN, 1)).rejects.toBeInstanceOf(ConflictException);
    expect(crowned.tx.delete).not.toHaveBeenCalled();
  });
});

describe('CatalogService: Trường', () => {
  const dto = { shortCode: ' new ', name: 'Trường Mới', emailDomain: 'NEW.edu.vn', hexColor: '#aabbcc' };

  it('chuẩn hoá mã / đuôi email / màu khi lưu', async () => {
    const { tx, catalog } = setup();
    await catalog.createUniversity(ADMIN, dto);
    expect(tx.insert).toHaveBeenCalledWith(
      University,
      expect.objectContaining({ short_code: 'NEW', short_name: 'NEW', email_domain: 'new.edu.vn', hex_color: '#AABBCC' }),
    );
  });

  it('trùng mã hoặc đuôi email (23505) -> 409', async () => {
    const { tx, catalog } = setup();
    const dup = Object.assign(new QueryFailedError('INSERT', [], new Error('dup')), { code: '23505' });
    tx.insert.mockRejectedValueOnce(dup);
    await expect(catalog.createUniversity(ADMIN, dto)).rejects.toBeInstanceOf(ConflictException);
  });

  it('không xoá Trường đã có Sinh viên', async () => {
    const { tx, catalog } = setup({ findOne: new Map([[University, { id: 'u' }]]), exists: new Map([[User, true]]) });
    await expect(catalog.deleteUniversity(ADMIN, 'u')).rejects.toBeInstanceOf(ConflictException);
    expect(tx.delete).not.toHaveBeenCalled();
  });
});
