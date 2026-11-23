import { BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AntiCheatService, buildGigoFilter } from './anti-cheat.service';
import { PERMANENT_BAN, UserModerationService } from './user-moderation.service';
import { AdminAuditService } from './admin-audit.service';
import { TelemetryService } from '../telemetry/telemetry.service';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { Season } from '../../entities/season.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';

const ADMIN = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const USER = '11111111-1111-4111-8111-111111111111';
const UNI = '33333333-3333-4333-8333-333333333333';
const LOG = '44444444-4444-4444-8444-444444444444';
const SESSION = '22222222-2222-4222-8222-222222222222';

/** EntityManager giả: findOne trả theo entity, ghi lại mọi update/increment. */
function fakeTx(rows: Map<unknown, unknown>) {
  return {
    findOne: jest.fn(async (entity: unknown) => rows.get(entity) ?? null),
    update: jest.fn(async () => ({ affected: 2 })),
    increment: jest.fn(async () => undefined),
    insert: jest.fn(async () => undefined),
  };
}

function setup(rows: Map<unknown, unknown>) {
  const tx = fakeTx(rows);
  const ds = { transaction: jest.fn((fn) => fn(tx)), query: jest.fn() } as unknown as DataSource;
  const audit = new AdminAuditService(ds);
  return {
    tx,
    ds,
    antiCheat: new AntiCheatService(ds, {} as TelemetryService, audit),
    moderation: new UserModerationService(ds, audit),
  };
}

describe('buildGigoFilter', () => {
  it('không lọc gì -> không có WHERE', () => {
    expect(buildGigoFilter({})).toEqual({ sql: '', params: [] });
  });

  it('mọi bộ lọc -> tham số đánh số đúng thứ tự, không nối chuỗi giá trị vào SQL', () => {
    const { sql, params } = buildGigoFilter({
      type: "ERR_202'; DROP TABLE users;--",
      universityId: UNI,
      from: '2026-11-01T00:00:00+07:00',
      to: '2026-11-08T00:00:00+07:00',
      reviewStatus: 'pending',
    });
    expect(sql).toBe(
      'WHERE g.rejection_type = $1 AND u.university_id = $2 AND g.created_at >= $3 AND g.created_at < $4 AND g.review_status = $5',
    );
    expect(params).toEqual(["ERR_202'; DROP TABLE users;--", UNI, '2026-11-01T00:00:00+07:00', '2026-11-08T00:00:00+07:00', 'pending']);
  });
});

describe('AntiCheatService.listLogs / topOffenders', () => {
  it('trang 3, 20 dòng -> LIMIT 20 OFFSET 40 sau tham số lọc; đếm tổng cùng bộ lọc', async () => {
    const { ds, antiCheat } = setup(new Map());
    (ds.query as jest.Mock).mockResolvedValueOnce([{ id: LOG }]).mockResolvedValueOnce([{ total: 41 }]);
    const res = await antiCheat.listLogs({ page: 3, limit: 20, type: 'ERR_201' });

    const [listSql, listParams] = (ds.query as jest.Mock).mock.calls[0];
    expect(listSql).toContain('WHERE g.rejection_type = $1');
    expect(listSql).toContain('LIMIT $2 OFFSET $3');
    expect(listParams).toEqual(['ERR_201', 20, 40]);
    expect((ds.query as jest.Mock).mock.calls[1][1]).toEqual(['ERR_201']);
    expect(res).toEqual({ items: [{ id: LOG }], total: 41, page: 3, limit: 20 });
  });

  it('top vi phạm gom bằng SQL theo số ngày, bỏ log báo nhầm', async () => {
    const { ds, antiCheat } = setup(new Map());
    (ds.query as jest.Mock).mockResolvedValueOnce([]);
    await antiCheat.topOffenders(30, 10);
    const [sql, params] = (ds.query as jest.Mock).mock.calls[0];
    expect(sql).toMatch(/GROUP BY u\.id/);
    expect(sql).toContain("review_status <> 'false_positive'");
    expect(params).toEqual([30, 10]);
  });
});

describe('AntiCheatService.review', () => {
  const log = { id: LOG, session_id: SESSION, review_status: 'pending' } as GigoAuditLog;
  const rejected = {
    id: SESSION,
    user_id: USER,
    status: 'REJECTED',
    distance_meters: 2500,
    created_at: new Date('2026-11-20T10:00:00Z'),
  } as RunningSession;
  const season = { season_number: 3, start_date: '2026-11-01', is_active: true } as Season;
  const owner = { id: USER, university_id: UNI } as User;

  it('false_positive + khôi phục: Phiên thành COMPLETED hợp lệ, cộng bù km cho Sinh viên và Trường, ghi nhật ký admin', async () => {
    const { tx, antiCheat } = setup(
      new Map<unknown, unknown>([[GigoAuditLog, log], [RunningSession, rejected], [Season, season], [User, owner]]),
    );
    const res = await antiCheat.review(ADMIN, LOG, 'false_positive', true);

    expect(res.restored).toEqual({ addedKm: 2.5, inCurrentSeason: true });
    expect(tx.update).toHaveBeenCalledWith(GigoAuditLog, LOG, expect.objectContaining({ review_status: 'false_positive', reviewed_by: ADMIN }));
    expect(tx.update).toHaveBeenCalledWith(RunningSession, SESSION, { status: 'COMPLETED', is_valid: true, rejection_reason: null });
    expect(tx.increment).toHaveBeenCalledWith(User, { id: USER }, 'personal_km', 2.5);
    expect(tx.increment).toHaveBeenCalledWith(University, { id: UNI }, 'total_season_km', 2.5);
    expect(tx.insert).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ admin_id: ADMIN, action: 'gigo.review', target_id: LOG }),
    );
  });

  it('Phiên thuộc Mùa giải trước: khôi phục hợp lệ nhưng không cộng km', async () => {
    const old = { ...rejected, created_at: new Date('2026-10-20T10:00:00Z') };
    const { tx, antiCheat } = setup(new Map<unknown, unknown>([[GigoAuditLog, log], [RunningSession, old], [Season, season]]));
    const res = await antiCheat.review(ADMIN, LOG, 'false_positive', true);
    expect(res.restored).toEqual({ addedKm: 0, inCurrentSeason: false });
    expect(tx.increment).not.toHaveBeenCalled();
  });

  it('false_positive không kèm khôi phục: chỉ lưu kết luận', async () => {
    const { tx, antiCheat } = setup(new Map<unknown, unknown>([[GigoAuditLog, log], [RunningSession, rejected]]));
    const res = await antiCheat.review(ADMIN, LOG, 'false_positive');
    expect(res.restored).toBeNull();
    expect(tx.update).toHaveBeenCalledTimes(1);
    expect(tx.increment).not.toHaveBeenCalled();
  });

  it('khôi phục lần hai (Phiên đã COMPLETED) không cộng km lần nữa', async () => {
    const { tx, antiCheat } = setup(
      new Map<unknown, unknown>([[GigoAuditLog, log], [RunningSession, { ...rejected, status: 'COMPLETED' }], [Season, season]]),
    );
    const res = await antiCheat.review(ADMIN, LOG, 'false_positive', true);
    expect(res.restored).toBeNull();
    expect(tx.increment).not.toHaveBeenCalled();
  });

  it('kết luận gian lận cho Phiên đã khôi phục -> 409 ERR_108', async () => {
    const { antiCheat } = setup(
      new Map<unknown, unknown>([[GigoAuditLog, log], [RunningSession, { ...rejected, status: 'COMPLETED' }]]),
    );
    await expect(antiCheat.review(ADMIN, LOG, 'confirmed_cheat')).rejects.toBeInstanceOf(ConflictException);
  });

  it('restoreSession với confirmed_cheat -> 400; log không tồn tại -> 404', async () => {
    const { antiCheat } = setup(new Map());
    expect(() => antiCheat.review(ADMIN, LOG, 'confirmed_cheat', true)).toThrow(BadRequestException);
    await expect(antiCheat.review(ADMIN, LOG, 'pending')).rejects.toBeInstanceOf(NotFoundException);
  });
});

describe('UserModerationService', () => {
  const student = { id: USER, role: 'user', banned_until: null } as User;

  beforeEach(() => jest.useFakeTimers().setSystemTime(new Date('2026-11-23T08:00:00Z')));
  afterEach(() => jest.useRealTimers());

  it('khoá có hạn: đặt banned_until, loại các Phiên ACTIVE để cron không cộng km, ghi nhật ký', async () => {
    const { tx, moderation } = setup(new Map<unknown, unknown>([[User, student]]));
    const until = new Date('2026-11-30T00:00:00Z');
    const res = await moderation.ban(ADMIN, USER, until, 'Xe máy');

    expect(tx.update).toHaveBeenCalledWith(User, USER, { banned_until: until });
    expect(tx.update).toHaveBeenCalledWith(
      RunningSession,
      { user_id: USER, status: 'ACTIVE' },
      expect.objectContaining({ status: 'REJECTED', is_valid: false, rejection_reason: 'ERR_106' }),
    );
    expect(res).toEqual({ userId: USER, bannedUntil: until, rejectedSessions: 2 });
    expect(tx.insert).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ action: 'user.ban', target_id: USER }));
  });

  it('bỏ trống until -> khoá vĩnh viễn', async () => {
    const { tx, moderation } = setup(new Map<unknown, unknown>([[User, student]]));
    await moderation.ban(ADMIN, USER, null, 'Fake GPS');
    expect(tx.update).toHaveBeenCalledWith(User, USER, { banned_until: PERMANENT_BAN });
  });

  it('until ở quá khứ -> 400; user không tồn tại -> 404; khoá admin -> 409', async () => {
    expect(() => setup(new Map()).moderation.ban(ADMIN, USER, new Date('2026-11-01T00:00:00Z'), 'x')).toThrow(
      BadRequestException,
    );
    await expect(setup(new Map()).moderation.ban(ADMIN, USER, null, 'abc')).rejects.toBeInstanceOf(NotFoundException);
    await expect(
      setup(new Map<unknown, unknown>([[User, { ...student, role: 'admin' }]])).moderation.ban(ADMIN, USER, null, 'abc'),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('gỡ khoá: banned_until = null và ghi nhật ký', async () => {
    const { tx, moderation } = setup(new Map<unknown, unknown>([[User, { ...student, banned_until: PERMANENT_BAN }]]));
    await moderation.unban(ADMIN, USER);
    expect(tx.update).toHaveBeenCalledWith(User, USER, { banned_until: null });
    expect(tx.insert).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ action: 'user.unban' }));
  });
});
