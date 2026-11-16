import { NotFoundException } from '@nestjs/common';
import * as h3 from 'h3-js';
import { Repository } from 'typeorm';
import { TurfService, NEUTRAL_HEX_COLOR, UPSERT_CLAIMED_HEXES_SQL } from './turf.service';
import { H3Hexagon } from '../../entities/h3-hexagon.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { Arena } from '../../entities/arena.entity';
import { H3Service } from './h3.service';
import { TurfGateway } from '../realtime/turf.gateway';

const ARENA_ID = '11111111-1111-4111-8111-111111111111';
const HUTECH_ID = '22222222-2222-4222-8222-222222222222';
const PATROLLED = new Date('2026-11-04T10:00:00.000Z');

const ownedHex = {
  h3_index: '8a65b56718b7fff',
  arena_id: ARENA_ID,
  owner_university_id: HUTECH_ID,
  ownerUniversity: { id: HUTECH_ID, short_code: 'HUTECH', hex_color: '#FFCC00' },
  shield_hp: 80,
  last_patrolled_at: PATROLLED,
} as unknown as H3Hexagon;

const neutralHex = {
  h3_index: '8a65b5671d6ffff',
  arena_id: null,
  owner_university_id: null,
  ownerUniversity: null,
  shield_hp: 100,
  last_patrolled_at: PATROLLED,
} as unknown as H3Hexagon;

describe('TurfService: đọc bản đồ (getArenaHexagons, getArenas)', () => {
  let service: TurfService;
  let hexRepo: { find: jest.Mock; count: jest.Mock };
  let arenaRepo: { find: jest.Mock; exists: jest.Mock };

  beforeEach(() => {
    hexRepo = { find: jest.fn(), count: jest.fn() };
    arenaRepo = { find: jest.fn(), exists: jest.fn() };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const unused = {} as Repository<any>;
    service = new TurfService(
      hexRepo as unknown as Repository<H3Hexagon>,
      unused,
      arenaRepo as unknown as Repository<Arena>,
      {} as H3Service,
      {} as TurfGateway,
    );
  });

  describe('getArenaHexagons', () => {
    it('bỏ trống arenaId thì trả toàn bộ ô, không kiểm Đấu trường', async () => {
      hexRepo.find.mockResolvedValue([ownedHex, neutralHex]);

      const res = await service.getArenaHexagons();

      expect(arenaRepo.exists).not.toHaveBeenCalled();
      expect(hexRepo.find).toHaveBeenCalledWith({ where: {}, relations: ['ownerUniversity'] });
      expect(res).toHaveLength(2);
    });

    it('ô có chủ mang mã và màu trường, kèm arenaId', async () => {
      hexRepo.find.mockResolvedValue([ownedHex]);

      const [hex] = await service.getArenaHexagons();

      expect(hex).toEqual({
        h3Index: '8a65b56718b7fff',
        arenaId: ARENA_ID,
        ownerUniversityId: HUTECH_ID,
        universityCode: 'HUTECH',
        hexColor: '#FFCC00',
        shieldHp: 80,
        lastPatrolledAt: PATROLLED,
      });
    });

    it('ô trung lập trả null cho chủ, mã trường, arenaId và màu trung lập', async () => {
      hexRepo.find.mockResolvedValue([neutralHex]);

      const [hex] = await service.getArenaHexagons();

      expect(hex.ownerUniversityId).toBeNull();
      expect(hex.universityCode).toBeNull();
      expect(hex.arenaId).toBeNull();
      expect(hex.hexColor).toBe(NEUTRAL_HEX_COLOR);
    });

    it('có arenaId hợp lệ thì chỉ lấy ô của Đấu trường đó', async () => {
      arenaRepo.exists.mockResolvedValue(true);
      hexRepo.find.mockResolvedValue([ownedHex]);

      await service.getArenaHexagons(ARENA_ID);

      expect(arenaRepo.exists).toHaveBeenCalledWith({ where: { id: ARENA_ID } });
      expect(hexRepo.find).toHaveBeenCalledWith({
        where: { arena_id: ARENA_ID },
        relations: ['ownerUniversity'],
      });
    });

    it('arenaId không tồn tại thì ném 404 ERR_303 và không truy vấn ô', async () => {
      arenaRepo.exists.mockResolvedValue(false);

      const call = service.getArenaHexagons(ARENA_ID);

      await expect(call).rejects.toBeInstanceOf(NotFoundException);
      await expect(call).rejects.toMatchObject({ response: { code: 'ERR_303' } });
      expect(hexRepo.find).not.toHaveBeenCalled();
    });
  });

  describe('getArenas', () => {
    const boundary = {
      type: 'Polygon' as const,
      coordinates: [[[106.7185, 10.791], [106.7255, 10.791], [106.7255, 10.7985], [106.7185, 10.791]]],
    };

    it('chỉ lấy Đấu trường đang hoạt động, xếp theo tên', async () => {
      arenaRepo.find.mockResolvedValue([]);

      await service.getArenas();

      expect(arenaRepo.find).toHaveBeenCalledWith({ where: { is_active: true }, order: { name: 'ASC' } });
    });

    it('hexCount là số ô đếm thật, không dùng total_hexes', async () => {
      arenaRepo.find.mockResolvedValue([
        { id: ARENA_ID, name: 'Công Viên Landmark 81', description: 'Ven sông', total_hexes: 180, boundary_polygon: boundary },
      ]);
      hexRepo.count.mockResolvedValue(25);

      const [arena] = await service.getArenas();

      expect(hexRepo.count).toHaveBeenCalledWith({ where: { arena_id: ARENA_ID } });
      expect(arena).toEqual({
        id: ARENA_ID,
        name: 'Công Viên Landmark 81',
        description: 'Ven sông',
        hexCount: 25,
        boundary,
      });
    });

    it('thiếu mô tả hoặc ranh giới thì trả null', async () => {
      arenaRepo.find.mockResolvedValue([
        { id: ARENA_ID, name: 'Khu Đô Thị Sala', description: undefined, boundary_polygon: null },
      ]);
      hexRepo.count.mockResolvedValue(0);

      const [arena] = await service.getArenas();

      expect(arena.description).toBeNull();
      expect(arena.boundary).toBeNull();
      expect(arena.hexCount).toBe(0);
    });
  });
});

describe('TurfService: claimLoop', () => {
  const USER_ID = '33333333-3333-4333-8333-333333333333';
  const SESSION_ID = '44444444-4444-4444-8444-444444444444';
  const user = {
    id: USER_ID,
    email: 'sv@hutech.edu.vn',
    display_name: 'SV',
    university: { id: HUTECH_ID, name: 'HUTECH', short_code: 'HUTECH', hex_color: '#FFCC00' },
  };
  // Ô thật ở HUTECH (trong khu thi đấu), đặt tên theo thứ tự sắp xếp.
  const [a, b, c] = h3.gridDisk(h3.latLngToCell(10.8016, 106.7146, 10), 1).sort();
  const dto = { boundaryH3Indexes: [b, a], sessionId: SESSION_ID, arenaId: ARENA_ID };
  const activeSession = { id: SESSION_ID, user_id: USER_ID, status: 'ACTIVE', distance_meters: 1500 };

  let tx: { findOne: jest.Mock; query: jest.Mock; increment: jest.Mock; update: jest.Mock };
  let gateway: { broadcastHexClaimed: jest.Mock };
  let service: TurfService;

  beforeEach(() => {
    tx = {
      findOne: jest.fn().mockResolvedValue(activeSession),
      query: jest.fn(),
      increment: jest.fn(),
      update: jest.fn(),
    };
    gateway = { broadcastHexClaimed: jest.fn() };
    const hexRepo = { manager: { transaction: jest.fn((work) => work(tx)) } };
    service = new TurfService(
      hexRepo as unknown as Repository<H3Hexagon>,
      { findOne: jest.fn().mockResolvedValue(user) } as unknown as Repository<User>,
      { findOne: jest.fn().mockResolvedValue({ id: ARENA_ID, boundary_polygon: null }) } as unknown as Repository<Arena>,
      { calculateEnclosedHexes: () => [c, a, b] } as unknown as H3Service,
      gateway as unknown as TurfGateway,
    );
  });

  it('khoá đúng Phiên chạy của chính Sinh viên', async () => {
    await service.claimLoop(USER_ID, dto);

    expect(tx.findOne).toHaveBeenCalledWith(RunningSession, {
      where: { id: SESSION_ID, user_id: USER_ID },
      lock: { mode: 'pessimistic_write' },
    });
  });

  it('ghi cả lô ô bằng một câu lệnh, ô đã sắp xếp', async () => {
    await service.claimLoop(USER_ID, dto);

    expect(tx.query).toHaveBeenCalledTimes(1);
    expect(tx.query).toHaveBeenCalledWith(UPSERT_CLAIMED_HEXES_SQL, [[a, b, c], ARENA_ID, HUTECH_ID]);
  });

  it('không gửi arenaId thì truyền null để giữ Đấu trường sẵn có của ô', async () => {
    await service.claimLoop(USER_ID, { ...dto, arenaId: undefined });

    expect(tx.query.mock.calls[0][1][1]).toBeNull();
    expect(UPSERT_CLAIMED_HEXES_SQL).toContain('COALESCE(EXCLUDED.arena_id');
  });

  it('Km lấy từ quãng đường của Phiên chạy và đóng phiên', async () => {
    const res = await service.claimLoop(USER_ID, dto);

    expect(tx.increment).toHaveBeenCalledWith(University, { id: HUTECH_ID }, 'total_season_km', 1.5);
    expect(tx.increment).toHaveBeenCalledWith(User, { id: USER_ID }, 'personal_km', 1.5);
    expect(tx.update).toHaveBeenCalledWith(RunningSession, SESSION_ID, {
      status: 'COMPLETED',
      session_type: 'ARENA_LOOP',
      hex_count: 3,
    });
    expect(res).toMatchObject({ claimedCount: 3, addedKm: 1.5 });
  });

  it.each([
    ['không tồn tại hoặc của người khác', null, 'ERR_204'],
    ['đã dùng để chiếm đất', { ...activeSession, status: 'COMPLETED' }, 'ERR_204'],
    ['đã bị loại vì xe máy', { ...activeSession, status: 'REJECTED', rejection_reason: 'ERR_202' }, 'ERR_202'],
  ])('Phiên chạy %s thì từ chối, không ghi gì', async (_name, session, code) => {
    tx.findOne.mockResolvedValue(session);

    await expect(service.claimLoop(USER_ID, dto)).rejects.toMatchObject({ response: { code } });
    expect(tx.query).not.toHaveBeenCalled();
    expect(tx.increment).not.toHaveBeenCalled();
    expect(gateway.broadcastHexClaimed).not.toHaveBeenCalled();
  });

  it('broadcast sau khi transaction xong', async () => {
    await service.claimLoop(USER_ID, dto);

    expect(gateway.broadcastHexClaimed.mock.invocationCallOrder[0]).toBeGreaterThan(
      tx.update.mock.invocationCallOrder[0],
    );
  });

  it('hex_claimed đúng hợp đồng #3 và không chứa thông tin cá nhân', async () => {
    await service.claimLoop(USER_ID, dto);

    const payload = gateway.broadcastHexClaimed.mock.calls[0][0];
    expect(payload).toEqual({
      universityId: HUTECH_ID,
      universityCode: 'HUTECH',
      hexColor: '#FFCC00',
      claimedHexes: [c, a, b],
      arenaId: ARENA_ID,
      claimedAt: expect.stringMatching(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/),
    });
    expect(JSON.stringify(payload)).not.toContain(user.email);
  });

  it('không gửi arenaId thì hex_claimed mang arenaId null', async () => {
    await service.claimLoop(USER_ID, { ...dto, arenaId: undefined });

    expect(gateway.broadcastHexClaimed.mock.calls[0][0].arenaId).toBeNull();
  });

  it('transaction lỗi thì ném lỗi và không broadcast', async () => {
    tx.increment.mockRejectedValue(new Error('db down'));

    await expect(service.claimLoop(USER_ID, dto)).rejects.toThrow('db down');
    expect(gateway.broadcastHexClaimed).not.toHaveBeenCalled();
  });
});

describe('TurfService: claimLoop với H3Service thật (không giả lập flood fill)', () => {
  const USER_ID = '33333333-3333-4333-8333-333333333333';
  const SESSION_ID = '44444444-4444-4444-8444-444444444444';
  const center = h3.latLngToCell(10.8016, 106.7146, 10);
  const ring = h3.gridRingUnsafe(center, 3);
  const expected = [...ring, ...h3.gridDisk(center, 2)].sort();

  // Ranh giới GeoJSON [lng, lat] hình vuông ±0.01° (~1 km) quanh một điểm.
  const square = (lat: number, lng: number) => ({
    type: 'Polygon' as const,
    coordinates: [[[lng - 0.01, lat - 0.01], [lng + 0.01, lat - 0.01], [lng + 0.01, lat + 0.01], [lng - 0.01, lat + 0.01], [lng - 0.01, lat - 0.01]]],
  });

  let tx: { findOne: jest.Mock; query: jest.Mock; increment: jest.Mock; update: jest.Mock };
  let gateway: { broadcastHexClaimed: jest.Mock };
  let arenaRepo: { findOne: jest.Mock };
  let service: TurfService;

  beforeEach(() => {
    arenaRepo = { findOne: jest.fn().mockResolvedValue({ id: ARENA_ID, boundary_polygon: square(10.8016, 106.7146) }) };
    tx = {
      findOne: jest.fn().mockResolvedValue({ id: SESSION_ID, user_id: USER_ID, status: 'ACTIVE', distance_meters: 1200 }),
      query: jest.fn(),
      increment: jest.fn(),
      update: jest.fn(),
    };
    gateway = { broadcastHexClaimed: jest.fn() };
    service = new TurfService(
      { manager: { transaction: jest.fn((work) => work(tx)) } } as unknown as Repository<H3Hexagon>,
      {
        findOne: jest.fn().mockResolvedValue({
          id: USER_ID,
          university: { id: HUTECH_ID, short_code: 'HUTECH', hex_color: '#FFCC00' },
        }),
      } as unknown as Repository<User>,
      arenaRepo as unknown as Repository<Arena>,
      new H3Service(),
      gateway as unknown as TurfGateway,
    );
  });

  it('vòng 18 ô biên: ghi và broadcast đủ 37 ô, gồm cả 19 ô bên trong', async () => {
    const res = await service.claimLoop(USER_ID, { boundaryH3Indexes: ring, sessionId: SESSION_ID, arenaId: ARENA_ID });

    expect(tx.query.mock.calls[0][1][0]).toEqual(expected);
    expect([...gateway.broadcastHexClaimed.mock.calls[0][0].claimedHexes].sort()).toEqual(expected);
    expect(res).toMatchObject({ claimedCount: 37 });
  });

  it('đường biên sai thứ tự: ERR_302, không mở transaction, không broadcast', async () => {
    const shuffled = [0, 9, 3, 12, 6, 15, 1, 10, 4, 13, 7, 16, 2, 11, 5, 14, 8, 17].map((i) => ring[i]);

    await expect(
      service.claimLoop(USER_ID, { boundaryH3Indexes: shuffled, sessionId: SESSION_ID }),
    ).rejects.toMatchObject({ response: { code: 'ERR_302' } });
    expect(tx.findOne).not.toHaveBeenCalled();
    expect(gateway.broadcastHexClaimed).not.toHaveBeenCalled();
  });

  describe('H4: vòng chạy phải nằm trong Đấu trường / khu thi đấu', () => {
    const claim = (boundaryH3Indexes: string[], arenaId?: string) =>
      service.claimLoop(USER_ID, { boundaryH3Indexes, sessionId: SESSION_ID, arenaId });
    const expectNothingWritten = () => {
      expect(tx.findOne).not.toHaveBeenCalled();
      expect(gateway.broadcastHexClaimed).not.toHaveBeenCalled();
    };

    it('arenaId không tồn tại hoặc Đấu trường đã tắt: 404 ERR_303 (trước đây lỗi khoá ngoại → 500), không ghi gì', async () => {
      arenaRepo.findOne.mockResolvedValue(null);

      await expect(claim(ring, ARENA_ID)).rejects.toMatchObject({ status: 404, response: { code: 'ERR_303' } });
      expect(arenaRepo.findOne).toHaveBeenCalledWith({ where: { id: ARENA_ID, is_active: true } });
      expectNothingWritten();
    });

    it('vòng nằm ngoài ranh giới Đấu trường đã chọn: 400 ERR_304, không ghi gì', async () => {
      arenaRepo.findOne.mockResolvedValue({ id: ARENA_ID, boundary_polygon: square(10.7951, 106.7219) }); // Landmark 81

      await expect(claim(ring, ARENA_ID)).rejects.toMatchObject({ status: 400, response: { code: 'ERR_304' } });
      expectNothingWritten();
    });

    it('vòng vắt qua mép Đấu trường (có ô bên trong ở ngoài): ERR_304', async () => {
      arenaRepo.findOne.mockResolvedValue({ id: ARENA_ID, boundary_polygon: square(10.8016 + 0.012, 106.7146) });

      await expect(claim(ring, ARENA_ID)).rejects.toMatchObject({ response: { code: 'ERR_304' } });
      expectNothingWritten();
    });

    it('không gửi arenaId, vòng trong khu Bình Thạnh: chiếm bình thường, không tra Đấu trường', async () => {
      await expect(claim(ring)).resolves.toMatchObject({ claimedCount: 37 });
      expect(arenaRepo.findOne).not.toHaveBeenCalled();
    });

    it('không gửi arenaId, vòng ở Hà Nội: ERR_304', async () => {
      const hanoi = h3.gridRingUnsafe(h3.latLngToCell(21.0285, 105.8542, 10), 3);

      await expect(claim(hanoi)).rejects.toMatchObject({ response: { code: 'ERR_304' } });
      expectNothingWritten();
    });

    it('Đấu trường chưa có ranh giới: dùng khung khu thi đấu', async () => {
      arenaRepo.findOne.mockResolvedValue({ id: ARENA_ID, boundary_polygon: null });

      await expect(claim(ring, ARENA_ID)).resolves.toMatchObject({ claimedCount: 37 });
    });
  });
});
