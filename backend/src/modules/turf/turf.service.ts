import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import * as h3 from 'h3-js';
import { H3Hexagon } from '../../entities/h3-hexagon.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { H3Service, H3_RESOLUTION } from './h3.service';
import { TurfGateway } from '../realtime/turf.gateway';
import { ClaimLoopDto } from './dto/claim-loop.dto';
import { Arena } from '../../entities/arena.entity';
import { ArenaResponseDto, HexagonResponseDto } from './dto/turf-response.dto';

/** Màu ô trung lập; khớp CampusColors.neutralHex phía client. */
export const NEUTRAL_HEX_COLOR = '#44FFFFFF';

/** Khung bao khu thi đấu Bình Thạnh; khớp PlayArea phía client. */
export const PLAY_AREA = { minLat: 10.755, maxLat: 10.83, minLng: 106.695, maxLng: 106.745 };

const arenaNotFound = () =>
  new NotFoundException({ code: 'ERR_303', message: 'ARENA_NOT_FOUND: Không tìm thấy Đấu trường.' });

/**
 * Chiếm cả lô ô trong một câu lệnh. Ô đã thuộc Đấu trường giữ nguyên `arena_id`
 * khi Vòng khép không gửi `arenaId`.
 */
export const UPSERT_CLAIMED_HEXES_SQL = `
  INSERT INTO public.h3_hexagons
    (h3_index, arena_id, owner_university_id, shield_hp, last_patrolled_at, updated_at)
  SELECT unnest($1::varchar[]), $2::uuid, $3::uuid, 100, now(), now()
  ON CONFLICT (h3_index) DO UPDATE SET
    arena_id = COALESCE(EXCLUDED.arena_id, public.h3_hexagons.arena_id),
    owner_university_id = EXCLUDED.owner_university_id,
    shield_hp = EXCLUDED.shield_hp,
    last_patrolled_at = EXCLUDED.last_patrolled_at,
    updated_at = EXCLUDED.updated_at`;

@Injectable()
export class TurfService {
  constructor(
    @InjectRepository(H3Hexagon)
    private readonly hexRepository: Repository<H3Hexagon>,
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(Arena)
    private readonly arenaRepository: Repository<Arena>,
    private readonly h3Service: H3Service,
    private readonly turfGateway: TurfGateway,
  ) {}

  /**
   * Trạng thái các ô H3. Bỏ trống `arenaId` thì trả toàn bộ ô (client tải một lần, ticket #6).
   * `arenaId` không tồn tại → 404 ERR_303.
   */
  async getArenaHexagons(arenaId?: string): Promise<HexagonResponseDto[]> {
    if (arenaId && !(await this.arenaRepository.exists({ where: { id: arenaId } }))) {
      throw arenaNotFound();
    }

    const hexes = await this.hexRepository.find({
      where: arenaId ? { arena_id: arenaId } : {},
      relations: ['ownerUniversity'],
    });

    return hexes.map((h) => ({
      h3Index: h.h3_index,
      arenaId: h.arena_id ?? null,
      ownerUniversityId: h.owner_university_id ?? null,
      universityCode: h.ownerUniversity?.short_code ?? null,
      hexColor: h.ownerUniversity?.hex_color ?? NEUTRAL_HEX_COLOR,
      shieldHp: h.shield_hp,
      lastPatrolledAt: h.last_patrolled_at,
    }));
  }

  /** Danh sách Đấu trường đang hoạt động, kèm số ô đếm thật và ranh giới GeoJSON. */
  async getArenas(): Promise<ArenaResponseDto[]> {
    const arenas = await this.arenaRepository.find({
      where: { is_active: true },
      order: { name: 'ASC' },
    });

    // Chỉ vài Đấu trường nên đếm từng cái là đủ, không cần GROUP BY.
    return Promise.all(
      arenas.map(async (a) => ({
        id: a.id,
        name: a.name,
        description: a.description ?? null,
        hexCount: await this.hexRepository.count({ where: { arena_id: a.id } }),
        boundary: a.boundary_polygon ?? null,
      })),
    );
  }

  async claimLoop(userId: string, dto: ClaimLoopDto) {
    const user = await this.userRepository.findOne({
      where: { id: userId },
      relations: ['university'],
    });

    if (!user || !user.university) {
      throw new NotFoundException('Không tìm thấy thông tin trường của sinh viên.');
    }

    // 1. Tính toán tất cả các ô H3 nằm trong vòng khép kín
    const claimedHexIndexes = this.h3Service.calculateEnclosedHexes(dto.boundaryH3Indexes);
    await this.assertInsideArena(claimedHexIndexes, dto.arenaId);

    // 2. Ghi đất, Km và lịch sử phiên chạy cùng một transaction: lỗi ở bước nào cũng không để lại dữ liệu dở dang.
    const distanceKm = await this.hexRepository.manager.transaction(async (tx) => {
      // Khoá dòng Phiên chạy: hai lần gửi cùng lúc không thể cộng Km hai lần.
      const session = await tx.findOne(RunningSession, {
        where: { id: dto.sessionId, user_id: userId },
        lock: { mode: 'pessimistic_write' },
      });
      this.assertClaimable(session);

      // Sắp xếp để hai Vòng khép chồng ô luôn khoá ô theo cùng thứ tự, tránh deadlock.
      await tx.query(UPSERT_CLAIMED_HEXES_SQL, [
        [...claimedHexIndexes].sort(),
        dto.arenaId || null,
        user.university.id,
      ]);

      // Km lấy từ quãng đường server đã tự cộng khi kiểm định (hợp đồng #3).
      const km = session.distance_meters / 1000.0;
      await tx.increment(University, { id: user.university.id }, 'total_season_km', km);
      await tx.increment(User, { id: user.id }, 'personal_km', km);

      await tx.update(RunningSession, session.id, {
        status: 'COMPLETED',
        session_type: 'ARENA_LOOP',
        hex_count: claimedHexIndexes.length,
      });
      return km;
    });

    // 3. Chỉ broadcast sau khi đã commit, để client không đổi màu theo dữ liệu chưa được lưu.
    this.turfGateway.broadcastHexClaimed({
      universityId: user.university.id,
      universityCode: user.university.short_code,
      hexColor: user.university.hex_color,
      claimedHexes: claimedHexIndexes,
      arenaId: dto.arenaId || null,
      claimedAt: new Date().toISOString(),
    });

    return {
      message: `Chúc mừng! Bạn đã chiếm ${claimedHexIndexes.length} ô lục giác cho ${user.university.name}!`,
      claimedCount: claimedHexIndexes.length,
      claimedHexes: claimedHexIndexes,
      addedKm: Number(distanceKm.toFixed(2)),
    };
  }

  /**
   * Mọi ô chiếm (biên + bên trong) phải nằm trong Đấu trường `arenaId` (tâm ô trong ranh giới, cùng cách
   * seed), hoặc trong khu thi đấu nếu không gửi `arenaId` / Đấu trường chưa có ranh giới.
   * shortcut: chưa đối chiếu biên với vệt GPS thật của Phiên chạy (server chưa lưu vệt); làm khi có lưu vệt.
   */
  private async assertInsideArena(cells: string[], arenaId?: string): Promise<void> {
    let inside = (cell: string) => {
      const [lat, lng] = h3.cellToLatLng(cell);
      return lat >= PLAY_AREA.minLat && lat <= PLAY_AREA.maxLat && lng >= PLAY_AREA.minLng && lng <= PLAY_AREA.maxLng;
    };
    if (arenaId) {
      const arena = await this.arenaRepository.findOne({ where: { id: arenaId, is_active: true } });
      if (!arena) throw arenaNotFound(); // Đấu trường đã tắt coi như không tồn tại, khớp getArenas
      if (arena.boundary_polygon) {
        const arenaCells = new Set(h3.polygonToCells(arena.boundary_polygon.coordinates, H3_RESOLUTION, true));
        inside = (cell) => arenaCells.has(cell);
      }
    }
    if (!cells.every(inside)) {
      throw new BadRequestException({
        code: 'ERR_304',
        message: arenaId
          ? 'OUT_OF_ARENA: Vòng chạy có ô nằm ngoài Đấu trường.'
          : 'OUT_OF_ARENA: Vòng chạy có ô nằm ngoài khu thi đấu Bình Thạnh.',
      });
    }
  }

  /** Chỉ Phiên chạy còn ACTIVE của chính Sinh viên mới được dùng để chiếm đất, và chỉ một lần. */
  private assertClaimable(session: RunningSession | null): void {
    if (!session) {
      throw new NotFoundException({
        code: 'ERR_204',
        message: 'SESSION_NOT_FOUND: Không tìm thấy Phiên chạy.',
      });
    }
    if (session.status === 'REJECTED') {
      throw new BadRequestException({
        code: session.rejection_reason ?? 'ERR_202',
        message: 'SESSION_REJECTED: Phiên chạy đã bị loại, không thể chiếm đất.',
      });
    }
    if (session.status !== 'ACTIVE') {
      throw new NotFoundException({
        code: 'ERR_204',
        message: 'SESSION_NOT_FOUND: Phiên chạy đã kết thúc.',
      });
    }
  }
}
