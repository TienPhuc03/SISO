import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { AdminGuard, NotBannedGuard, isBanned } from './account.guards';
import { User } from '../../entities/user.entity';

const NOW = new Date('2026-11-23T08:00:00Z');

function ctx(userId?: string): ExecutionContext {
  return {
    switchToHttp: () => ({ getRequest: () => ({ user: userId ? { userId } : undefined }) }),
  } as unknown as ExecutionContext;
}

function dataSource(user: Partial<User> | null) {
  const findOne = jest.fn().mockResolvedValue(user);
  return { ds: { getRepository: () => ({ findOne }) } as unknown as DataSource, findOne };
}

async function codeOf(p: Promise<unknown>) {
  try {
    await p;
  } catch (e) {
    expect(e).toBeInstanceOf(ForbiddenException);
    return ((e as ForbiddenException).getResponse() as { code: string }).code;
  }
  throw new Error('Expected rejection');
}

describe('isBanned', () => {
  it.each([
    [null, false],
    [new Date('2026-11-23T07:59:59Z'), false], // đã hết hạn
    [new Date('2026-11-23T08:00:00Z'), false], // hết hạn đúng lúc này
    [new Date('2026-11-23T08:00:01Z'), true],
    [new Date('9999-12-31T00:00:00Z'), true], // vĩnh viễn
  ])('banned_until=%s -> %s', (until, expected) => {
    expect(isBanned({ banned_until: until }, NOW)).toBe(expected);
  });

  it('không có user -> không bị cấm', () => expect(isBanned(null, NOW)).toBe(false));
});

describe('AdminGuard', () => {
  it('role admin -> cho qua, đọc role từ DB theo userId của JWT', async () => {
    const { ds, findOne } = dataSource({ id: 'u1', role: 'admin', banned_until: null });
    await expect(new AdminGuard(ds).canActivate(ctx('u1'))).resolves.toBe(true);
    expect(findOne).toHaveBeenCalledWith(expect.objectContaining({ where: { id: 'u1' } }));
  });

  it('role user -> 403 ERR_107', async () => {
    const { ds } = dataSource({ id: 'u1', role: 'user', banned_until: null });
    expect(await codeOf(new AdminGuard(ds).canActivate(ctx('u1')))).toBe('ERR_107');
  });

  it('user đã bị xoá -> 403 ERR_107', async () => {
    const { ds } = dataSource(null);
    expect(await codeOf(new AdminGuard(ds).canActivate(ctx('u1')))).toBe('ERR_107');
  });

  it('không có req.user (thiếu JwtAuthGuard) -> 403, không truy vấn DB', async () => {
    const { ds, findOne } = dataSource({ role: 'admin' });
    expect(await codeOf(new AdminGuard(ds).canActivate(ctx()))).toBe('ERR_107');
    expect(findOne).not.toHaveBeenCalled();
  });
});

describe('NotBannedGuard', () => {
  beforeEach(() => jest.useFakeTimers().setSystemTime(NOW));
  afterEach(() => jest.useRealTimers());

  it('không bị cấm -> cho qua', async () => {
    const { ds } = dataSource({ id: 'u1', role: 'user', banned_until: null, university_id: 'uni-1' });
    await expect(new NotBannedGuard(ds).canActivate(ctx('u1'))).resolves.toBe(true);
  });

  it('lệnh cấm đã hết hạn -> cho qua', async () => {
    const { ds } = dataSource({ id: 'u1', banned_until: new Date('2026-11-22T00:00:00Z'), university_id: 'uni-1' });
    await expect(new NotBannedGuard(ds).canActivate(ctx('u1'))).resolves.toBe(true);
  });

  it('đang bị cấm -> 403 ERR_106', async () => {
    const { ds } = dataSource({ id: 'u1', banned_until: new Date('2026-11-30T00:00:00Z') });
    expect(await codeOf(new NotBannedGuard(ds).canActivate(ctx('u1')))).toBe('ERR_106');
  });

  it('chưa chọn Trường -> 403 ERR_109', async () => {
    const { ds } = dataSource({ id: 'u1', role: 'user', banned_until: null, university_id: null as unknown as string });
    expect(await codeOf(new NotBannedGuard(ds).canActivate(ctx('u1')))).toBe('ERR_109');
  });
});
