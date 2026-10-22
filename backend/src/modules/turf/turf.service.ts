import { Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { H3Hexagon } from '../../entities/h3-hexagon.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { H3Service } from './h3.service';
import { TurfGateway } from '../realtime/turf.gateway';
import { ClaimLoopDto } from './dto/claim-loop.dto';

@Injectable()
export class TurfService {
  constructor(
    @InjectRepository(H3Hexagon)
    private readonly hexRepository: Repository<H3Hexagon>,
    @InjectRepository(University)
    private readonly uniRepository: Repository<University>,
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(RunningSession)
    private readonly sessionRepository: Repository<RunningSession>,
    private readonly h3Service: H3Service,
    private readonly turfGateway: TurfGateway,
  ) {}

  async getArenaHexagons(arenaId?: string) {
    const query = this.hexRepository
      .createQueryBuilder('hex')
      .leftJoinAndSelect('hex.ownerUniversity', 'uni');

    if (arenaId) {
      query.where('hex.arena_id = :arenaId', { arenaId });
    }

    const hexes = await query.getMany();
    return hexes.map((h) => ({
      h3Index: h.h3_index,
      ownerUniversityId: h.owner_university_id,
      universityCode: h.ownerUniversity?.short_code || null,
      hexColor: h.ownerUniversity?.hex_color || '#44FFFFFF',
      shieldHp: h.shield_hp,
      lastPatrolledAt: h.last_patrolled_at,
    }));
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

    // 2. Cập nhật quyền sở hữu các ô lục giác trong CSDL
    const now = new Date();
    for (const hexIndex of claimedHexIndexes) {
      await this.hexRepository.save({
        h3_index: hexIndex,
        arena_id: dto.arenaId || null,
        owner_university_id: user.university.id,
        shield_hp: 100,
        last_patrolled_at: now,
      });
    }

    // 3. Tích lũy Km cống hiến vào Quỹ Km của trường và cá nhân
    const distanceKm = dto.distanceMeters / 1000.0;
    await this.uniRepository.increment({ id: user.university.id }, 'total_season_km', distanceKm);
    await this.userRepository.increment({ id: user.id }, 'personal_km', distanceKm);

    // 4. Lưu lại lịch sử phiên chạy
    await this.sessionRepository.save({
      user_id: user.id,
      session_type: 'ARENA_LOOP',
      distance_meters: dto.distanceMeters,
      duration_seconds: dto.durationSeconds,
      hex_count: claimedHexIndexes.length,
      is_valid: true,
    });

    // 5. Broadcast WebSocket tới tất cả sinh viên
    this.turfGateway.broadcastHexClaimed({
      universityId: user.university.id,
      universityCode: user.university.short_code,
      hexColor: user.university.hex_color,
      claimedHexes: claimedHexIndexes,
      claimedBy: user.display_name || user.email,
    });

    return {
      success: true,
      message: `Chúc mừng! Bạn đã chiếm ${claimedHexIndexes.length} ô lục giác cho ${user.university.name}!`,
      claimedCount: claimedHexIndexes.length,
      claimedHexes: claimedHexIndexes,
      addedKm: Number(distanceKm.toFixed(2)),
    };
  }
}
