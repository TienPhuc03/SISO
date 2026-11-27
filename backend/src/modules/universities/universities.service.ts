import { randomBytes } from 'crypto';
import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource, EntityManager, QueryFailedError } from 'typeorm';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { AuthService } from '../auth/auth.service';
import { ChooseUniversityDto } from './dto/choose-university.dto';
import { foldVietnamese } from './fold-vietnamese';
import { universityChoice } from './university-lock';

/** Màu cho Trường Sinh viên tự thêm (admin đổi lại được). */
const AUTO_COLORS = ['#E53935', '#8E24AA', '#3949AB', '#039BE5', '#00897B', '#7CB342', '#FDD835', '#FB8C00', '#6D4C41', '#546E7A', '#D81B60', '#5E35B1'];

export const pickColor = (name: string) =>
  AUTO_COLORS[[...foldVietnamese(name)].reduce((h, ch) => (h * 31 + ch.charCodeAt(0)) >>> 0, 7) % AUTO_COLORS.length];

/** Mã nội bộ duy nhất cho Trường tự thêm, vd. "UEHCOSOV-3F2A". */
export const newShortCode = (shortName: string) =>
  `${foldVietnamese(shortName).toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 12) || 'TRUONG'}-${randomBytes(2).toString('hex').toUpperCase()}`;

@Injectable()
export class UniversitiesService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly auth: AuthService,
  ) {}

  /** Danh mục cho màn chọn Trường: Cụm, quận (kèm Cụm) và mọi Trường (app tự lọc gợi ý không dấu). */
  async catalog() {
    const q = (sql: string) => this.dataSource.query(sql);
    const [clusters, districts, universities] = await Promise.all([
      q(`SELECT code, name FROM public.clusters ORDER BY sort_order`),
      q(`SELECT name, cluster_code AS "clusterCode" FROM public.districts ORDER BY sort_order`),
      q(`SELECT u.id, COALESCE(u.short_name, u.short_code) AS "shortName", u.name, u.parent_name AS "parentName",
                u.aliases, u.district, d.cluster_code AS "clusterCode", u.hex_color AS color, u.is_verified AS verified
         FROM public.universities u LEFT JOIN public.districts d ON d.name = u.district
         ORDER BY u.name`),
    ]);
    return { clusters, districts, universities };
  }

  /** Chọn / đổi Trường theo luật khoá Mùa giải (ERR_112). Trả phiên mới vì JWT mang universityId. */
  async choose(userId: string, dto: ChooseUniversityDto) {
    await this.dataSource
      .transaction(async (tx) => {
        const user = await tx.findOne(User, { where: { id: userId }, lock: { mode: 'pessimistic_write' } });
        if (!user) throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy tài khoản.' });
        const uniId = dto.universityId ? await this.existing(tx, dto.universityId) : await this.findOrCreate(tx, dto, userId);
        if (uniId === user.university_id) return; // "Ở lại": không đổi gì, không khoá thêm

        const { season, lockedReason } = await universityChoice(tx, user);
        if (lockedReason) throw new ForbiddenException({ code: 'ERR_112', message: lockedReason });
        await tx.update(User, user.id, { university_id: uniId, university_season: season });
      })
      .catch((e) => {
        if (e instanceof QueryFailedError && (e as QueryFailedError & { code?: string }).code === '23505') {
          throw new ConflictException({ code: 'ERR_108', message: 'Trường này vừa được thêm. Hãy tìm lại trong danh sách.' });
        }
        throw e;
      });
    return this.auth.issueSession(userId);
  }

  private async existing(tx: EntityManager, id: string): Promise<string> {
    if (!(await tx.exists(University, { where: { id } }))) {
      throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy Trường.' });
    }
    return id;
  }

  /** Trùng tên (không dấu) hoặc trùng tên viết tắt cùng quận thì dùng Trường có sẵn, không tạo bản sao. */
  private async findOrCreate(tx: EntityManager, dto: ChooseUniversityDto, userId: string): Promise<string> {
    const name = dto.name!.trim().replace(/\s+/g, ' ');
    const shortName = dto.shortName!.trim().replace(/\s+/g, ' ');
    const [district] = await tx.query(`SELECT name FROM public.districts WHERE name = $1`, [dto.district]);
    if (!district) throw new BadRequestException({ code: 'ERR_113', message: 'Quận không hợp lệ. Hãy chọn trong danh sách.' });

    const all = await tx.find(University, { select: { id: true, name: true, short_name: true, short_code: true, district: true } });
    const same = all.find(
      (u) =>
        foldVietnamese(u.name) === foldVietnamese(name) ||
        (u.district === dto.district && foldVietnamese(u.short_name ?? u.short_code) === foldVietnamese(shortName)),
    );
    if (same) return same.id;

    const { identifiers } = await tx.insert(University, {
      short_code: newShortCode(shortName),
      short_name: shortName,
      name,
      district: dto.district,
      hex_color: pickColor(name),
      is_verified: false,
      created_by: userId,
    });
    return identifiers[0].id as string;
  }
}
