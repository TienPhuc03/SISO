import { NotFoundException } from '@nestjs/common';
import { Repository } from 'typeorm';
import { TurfService, NEUTRAL_HEX_COLOR } from './turf.service';
import { H3Hexagon } from '../../entities/h3-hexagon.entity';
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
      unused,
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
