import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource, QueryFailedError } from 'typeorm';
import { Arena } from '../../entities/arena.entity';
import { HallOfFame } from '../../entities/hall-of-fame.entity';
import { Season } from '../../entities/season.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { AdminAuditService } from './admin-audit.service';
import { CreateSeasonDto, MergeUniversityDto, UniversityDto, UpdateArenaDto, UpdateSeasonDto } from './dto/admin-catalog.dto';

const notFound = (what: string) => new NotFoundException({ code: 'HTTP_404', message: `Không tìm thấy ${what}.` });
const conflict = (message: string) => new ConflictException({ code: 'ERR_108', message });

/** Lỗi trùng khoá duy nhất -> 409; quận không có trong bảng districts (khoá ngoại) -> 400. */
function rethrowUnique(e: unknown, message: string): never {
  const code = e instanceof QueryFailedError ? (e as QueryFailedError & { code?: string }).code : undefined;
  if (code === '23505') throw conflict(message);
  if (code === '23503') throw new BadRequestException({ code: 'ERR_113', message: 'Quận không hợp lệ.' });
  throw e;
}

function assertRange(start: string, end: string) {
  if (start > end) throw new BadRequestException({ code: 'HTTP_400', message: 'Ngày bắt đầu phải trước hoặc bằng ngày kết thúc.' });
}

/** Quản lý Mùa giải, Trường, Đấu trường. Mọi thay đổi ghi nhật ký admin trong cùng transaction. */
@Injectable()
export class CatalogService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly audit: AdminAuditService,
  ) {}

  // ---------- Mùa giải ----------

  seasons() {
    return this.dataSource.query(`
      SELECT s.season_number AS "seasonNumber", to_char(s.start_date, 'YYYY-MM-DD') AS "startDate",
             to_char(s.end_date, 'YYYY-MM-DD') AS "endDate", s.is_active AS "isActive",
             COALESCE(json_agg(json_build_object(
               'clusterCode', h.cluster_code, 'id', h.champion_university_id,
               'code', COALESCE(u.short_name, u.short_code), 'color', u.hex_color, 'powerPct', h.composite_power_pct
             ) ORDER BY h.cluster_code) FILTER (WHERE h.id IS NOT NULL), '[]') AS champions
      FROM public.seasons s
      LEFT JOIN public.hall_of_fame h ON h.season_number = s.season_number
      LEFT JOIN public.universities u ON u.id = h.champion_university_id
      GROUP BY s.season_number
      ORDER BY s.season_number DESC`);
  }

  /** Chỉ một Mùa giải được mở: cron close_finished_season lấy Mùa giải mở có số lớn nhất. */
  createSeason(adminId: string, dto: CreateSeasonDto) {
    assertRange(dto.startDate, dto.endDate);
    return this.dataSource.transaction(async (tx) => {
      const [{ next }] = await tx.query(`SELECT COALESCE(MAX(season_number), 0) + 1 AS next FROM public.seasons`);
      const seasonNumber = dto.seasonNumber ?? Number(next);
      if (await tx.exists(Season, { where: { season_number: seasonNumber } })) throw conflict(`Mùa giải ${seasonNumber} đã tồn tại.`);
      if (dto.isActive) await tx.update(Season, { is_active: true }, { is_active: false });
      await tx.insert(Season, {
        season_number: seasonNumber,
        start_date: dto.startDate,
        end_date: dto.endDate,
        is_active: !!dto.isActive,
      });
      await this.audit.log(tx, adminId, 'season.create', 'season', String(seasonNumber), { ...dto });
      return { seasonNumber };
    });
  }

  updateSeason(adminId: string, seasonNumber: number, dto: UpdateSeasonDto) {
    return this.dataSource.transaction(async (tx) => {
      const season = await tx.findOne(Season, { where: { season_number: seasonNumber }, lock: { mode: 'pessimistic_write' } });
      if (!season) throw notFound(`Mùa giải ${seasonNumber}`);
      const startDate = dto.startDate ?? season.start_date;
      const endDate = dto.endDate ?? season.end_date;
      assertRange(String(startDate), String(endDate));
      if (dto.isActive) await tx.update(Season, { is_active: true }, { is_active: false });
      await tx.update(Season, seasonNumber, {
        start_date: startDate,
        end_date: endDate,
        ...(dto.isActive !== undefined && { is_active: dto.isActive }),
      });
      await this.audit.log(tx, adminId, 'season.update', 'season', String(seasonNumber), {
        before: { startDate: season.start_date, endDate: season.end_date, isActive: season.is_active },
        after: { ...dto },
      });
      return { seasonNumber };
    });
  }

  /** Không xoá Mùa giải đang mở hay đã có Quán quân (Hall of Fame xoá theo dây chuyền). */
  deleteSeason(adminId: string, seasonNumber: number) {
    return this.dataSource.transaction(async (tx) => {
      const season = await tx.findOne(Season, { where: { season_number: seasonNumber } });
      if (!season) throw notFound(`Mùa giải ${seasonNumber}`);
      if (season.is_active) throw conflict('Không thể xoá Mùa giải đang mở.');
      if (await tx.exists(HallOfFame, { where: { season_number: seasonNumber } }))
        throw conflict('Mùa giải đã có Quán quân trong Đại sảnh Danh vọng, không thể xoá.');
      await tx.delete(Season, seasonNumber);
      await this.audit.log(tx, adminId, 'season.delete', 'season', String(seasonNumber), {
        startDate: season.start_date,
        endDate: season.end_date,
      });
      return { seasonNumber };
    });
  }

  // ---------- Trường ----------

  createUniversity(adminId: string, dto: UniversityDto) {
    return this.dataSource
      .transaction(async (tx) => {
        const { identifiers } = await tx.insert(University, this.toUniversity(dto));
        const id = identifiers[0].id as string;
        await this.audit.log(tx, adminId, 'university.create', 'university', id, { ...dto });
        return { id };
      })
      .catch((e) => rethrowUnique(e, 'Mã trường, tên trường hoặc đuôi email đã được dùng.'));
  }

  updateUniversity(adminId: string, id: string, dto: UniversityDto) {
    return this.dataSource
      .transaction(async (tx) => {
        const before = await tx.findOne(University, { where: { id } });
        if (!before) throw notFound('Trường');
        await tx.update(University, id, this.toUniversity(dto));
        await this.audit.log(tx, adminId, 'university.update', 'university', id, {
          before: {
            shortCode: before.short_code,
            name: before.name,
            emailDomain: before.email_domain,
            hexColor: before.hex_color,
          },
          after: { ...dto },
        });
        return { id };
      })
      .catch((e) => rethrowUnique(e, 'Mã trường, tên trường hoặc đuôi email đã được dùng.'));
  }

  /** Duyệt Trường Sinh viên tự thêm (bỏ nhãn "chờ duyệt"). */
  verifyUniversity(adminId: string, id: string) {
    return this.dataSource.transaction(async (tx) => {
      const uni = await tx.findOne(University, { where: { id } });
      if (!uni) throw notFound('Trường');
      await tx.update(University, id, { is_verified: true });
      await this.audit.log(tx, adminId, 'university.verify', 'university', id, { shortCode: uni.short_code, name: uni.name });
      return { id };
    });
  }

  /**
   * Gộp Trường trùng vào Trường giữ lại: chuyển Sinh viên, Ô đất, Quỹ Km và Quán quân sang rồi xoá Trường trùng.
   * Sinh viên bị chuyển không bị khoá thêm (giữ nguyên university_season).
   */
  mergeUniversity(adminId: string, id: string, dto: MergeUniversityDto) {
    if (id === dto.targetId) throw new BadRequestException({ code: 'HTTP_400', message: 'Không thể gộp Trường vào chính nó.' });
    return this.dataSource.transaction(async (tx) => {
      const [source, target] = await Promise.all([
        tx.findOne(University, { where: { id } }),
        tx.findOne(University, { where: { id: dto.targetId } }),
      ]);
      if (!source || !target) throw notFound('Trường');
      const [, moved] = await tx.query(`UPDATE public.users SET university_id = $2 WHERE university_id = $1`, [id, target.id]);
      await tx.query(`UPDATE public.h3_hexagons SET owner_university_id = $2 WHERE owner_university_id = $1`, [id, target.id]);
      await tx.query(`UPDATE public.hall_of_fame SET champion_university_id = $2 WHERE champion_university_id = $1`, [id, target.id]);
      await tx.increment(University, { id: target.id }, 'total_season_km', source.total_season_km ?? 0);
      await tx.delete(University, id);
      await this.audit.log(tx, adminId, 'university.merge', 'university', target.id, {
        merged: { id, shortCode: source.short_code, name: source.name },
        movedStudents: moved ?? null,
      });
      return { id: target.id };
    });
  }

  /** Chỉ xoá Trường chưa có Sinh viên nào (xoá sẽ làm mồ côi Sinh viên và Lãnh thổ). */
  deleteUniversity(adminId: string, id: string) {
    return this.dataSource.transaction(async (tx) => {
      const uni = await tx.findOne(University, { where: { id } });
      if (!uni) throw notFound('Trường');
      if (await tx.exists(User, { where: { university_id: id } })) throw conflict('Trường đã có Sinh viên, không thể xoá.');
      await tx.query(`UPDATE public.h3_hexagons SET owner_university_id = NULL, shield_hp = 0 WHERE owner_university_id = $1`, [id]);
      await tx.delete(University, id);
      await this.audit.log(tx, adminId, 'university.delete', 'university', id, { shortCode: uni.short_code, name: uni.name });
      return { id };
    });
  }

  private toUniversity(dto: UniversityDto): Partial<University> {
    const code = dto.shortCode.trim().toUpperCase();
    return {
      short_code: code,
      short_name: dto.shortName?.trim() || code,
      name: dto.name.trim(),
      email_domain: dto.emailDomain?.trim().toLowerCase() || null,
      district: dto.district,
      parent_name: dto.parentName?.trim() || null,
      aliases: dto.aliases?.trim() || null,
      hex_color: dto.hexColor.toUpperCase(),
      secondary_color: dto.secondaryColor?.toUpperCase() ?? null,
      logo_url: dto.logoUrl ?? null,
    } as Partial<University>;
  }

  // ---------- Đấu trường ----------

  /** Mọi Đấu trường (kể cả đang tắt) kèm số ô thật và số ô đang có chủ. */
  arenas() {
    return this.dataSource.query(`
      SELECT a.id, a.name, a.description, a.is_active AS "isActive",
             COUNT(h.h3_index)::int AS "hexCount",
             COUNT(h.h3_index) FILTER (WHERE h.owner_university_id IS NOT NULL)::int AS "ownedCount"
      FROM public.arenas a LEFT JOIN public.h3_hexagons h ON h.arena_id = a.id
      GROUP BY a.id ORDER BY a.name`);
  }

  updateArena(adminId: string, id: string, dto: UpdateArenaDto) {
    return this.dataSource.transaction(async (tx) => {
      const arena = await tx.findOne(Arena, { where: { id } });
      if (!arena) throw notFound('Đấu trường');
      await tx.update(Arena, id, {
        ...(dto.isActive !== undefined && { is_active: dto.isActive }),
        ...(dto.name !== undefined && { name: dto.name.trim() }),
        ...(dto.description !== undefined && { description: dto.description.trim() }),
      });
      await this.audit.log(tx, adminId, 'arena.update', 'arena', id, {
        before: { name: arena.name, isActive: arena.is_active },
        after: { ...dto },
      });
      return { id };
    });
  }
}
