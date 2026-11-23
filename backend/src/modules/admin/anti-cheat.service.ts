import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource, EntityManager } from 'typeorm';
import { GigoAuditLog, GigoReviewStatus } from '../../entities/gigo-audit-log.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { GpsPoint } from '../../entities/session-window.entity';
import { Season } from '../../entities/season.entity';
import { University } from '../../entities/university.entity';
import { User } from '../../entities/user.entity';
import { TelemetryService } from '../telemetry/telemetry.service';
import { AdminAuditService } from './admin-audit.service';
import { GigoLogQueryDto } from './dto/admin-query.dto';

/** Điều kiện WHERE có tham số ($1, $2, ...) cho danh sách nhật ký GIGO. */
export function buildGigoFilter(q: Omit<GigoLogQueryDto, 'page' | 'limit'>) {
  const params: unknown[] = [];
  const where: string[] = [];
  if (q.type) where.push(`g.rejection_type = $${params.push(q.type)}`);
  if (q.universityId) where.push(`u.university_id = $${params.push(q.universityId)}`);
  if (q.userId) where.push(`g.user_id = $${params.push(q.userId)}`);
  if (q.from) where.push(`g.created_at >= $${params.push(q.from)}`);
  if (q.to) where.push(`g.created_at < $${params.push(q.to)}`);
  if (q.reviewStatus) where.push(`g.review_status = $${params.push(q.reviewStatus)}`);
  return { sql: where.length ? `WHERE ${where.join(' AND ')}` : '', params };
}

/** Mốc bắt đầu Mùa giải đang mở (00:00 giờ VN); null nếu không có Mùa giải nào mở. */
export async function currentSeasonStart(manager: EntityManager): Promise<Date | null> {
  const season = await manager.findOne(Season, { where: { is_active: true }, order: { season_number: 'DESC' } });
  return season ? new Date(`${season.start_date}T00:00:00+07:00`) : null;
}

const LOG_COLUMNS = `
  g.id, g.rejection_type AS "rejectionType", g.raw_gps_speed_mps AS "gpsSpeedMps",
  g.imu_cadence_spm AS "cadenceSpm", g.vertical_energy_g AS "verticalEnergyG", g.gps_accuracy_m AS "gpsAccuracyM",
  g.review_status AS "reviewStatus", g.reviewed_at AS "reviewedAt", r.email AS "reviewedByEmail",
  g.created_at AS "createdAt", g.session_id AS "sessionId", s.status AS "sessionStatus",
  s.distance_meters AS "sessionDistanceMeters",
  u.id AS "userId", u.email, u.display_name AS "displayName", u.banned_until AS "bannedUntil",
  un.short_code AS "universityCode", un.hex_color AS "universityColor"`;

const LOG_JOINS = `
  FROM public.gigo_audit_logs g
  LEFT JOIN public.users u ON u.id = g.user_id
  LEFT JOIN public.universities un ON un.id = u.university_id
  LEFT JOIN public.running_sessions s ON s.id = g.session_id
  LEFT JOIN public.users r ON r.id = g.reviewed_by`;

@Injectable()
export class AntiCheatService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly telemetry: TelemetryService,
    private readonly audit: AdminAuditService,
  ) {}

  /** Danh sách Trường cho bộ lọc / tô màu. */
  universities() {
    return this.dataSource.query(
      `SELECT id, short_code AS "shortCode", name, email_domain AS "emailDomain", hex_color AS "hexColor"
       FROM public.universities ORDER BY short_code`,
    );
  }

  async listLogs(q: GigoLogQueryDto) {
    const { sql, params } = buildGigoFilter(q);
    const n = params.length;
    const [items, [{ total }]] = await Promise.all([
      this.dataSource.query(
        `SELECT ${LOG_COLUMNS} ${LOG_JOINS} ${sql} ORDER BY g.created_at DESC LIMIT $${n + 1} OFFSET $${n + 2}`,
        [...params, q.limit, (q.page - 1) * q.limit],
      ),
      this.dataSource.query(`SELECT COUNT(*)::int AS total ${LOG_JOINS} ${sql}`, params),
    ]);
    return { items, total, page: q.page, limit: q.limit };
  }

  /** Sinh viên có nhiều nhật ký GIGO nhất trong `days` ngày qua (không tính log đã kết luận báo nhầm). */
  topOffenders(days: number, limit: number) {
    return this.dataSource.query(
      `SELECT u.id AS "userId", u.email, u.display_name AS "displayName", u.banned_until AS "bannedUntil",
              un.short_code AS "universityCode", un.hex_color AS "universityColor",
              COUNT(*)::int AS violations,
              COUNT(*) FILTER (WHERE g.review_status = 'confirmed_cheat')::int AS confirmed,
              COUNT(*) FILTER (WHERE g.review_status = 'pending')::int AS pending,
              array_agg(DISTINCT g.rejection_type) AS types,
              MAX(g.created_at) AS "lastAt"
       FROM public.gigo_audit_logs g
       JOIN public.users u ON u.id = g.user_id
       LEFT JOIN public.universities un ON un.id = u.university_id
       WHERE g.created_at >= now() - make_interval(days => $1) AND g.review_status <> 'false_positive'
       GROUP BY u.id, un.id
       ORDER BY violations DESC, "lastAt" DESC
       LIMIT $2`,
      [days, limit],
    );
  }

  /**
   * Chi tiết Phiên chạy cho admin: tổng + cửa sổ + Đường chạy, kèm chủ Phiên và các nhật ký GIGO của nó.
   * Mỗi cửa sổ có thêm `points` ([lng, lat]) để tô màu đạt / không đạt trên bản đồ.
   */
  async sessionDetail(sessionId: string) {
    const session = await this.telemetry.getSession(null, sessionId);
    const [[user], auditLogs, tracks] = await Promise.all([
      this.dataSource.query(
        `SELECT u.id, u.email, u.display_name AS "displayName", u.banned_until AS "bannedUntil",
                un.short_code AS "universityCode", un.hex_color AS "universityColor"
         FROM public.running_sessions s JOIN public.users u ON u.id = s.user_id
         LEFT JOIN public.universities un ON un.id = u.university_id WHERE s.id = $1`,
        [sessionId],
      ),
      this.dataSource.query(`SELECT ${LOG_COLUMNS} ${LOG_JOINS} WHERE g.session_id = $1 ORDER BY g.created_at`, [
        sessionId,
      ]),
      this.dataSource.query(
        `SELECT seq, gps_points AS "gpsPoints" FROM public.session_windows WHERE session_id = $1`,
        [sessionId],
      ) as Promise<{ seq: number; gpsPoints: GpsPoint[] }[]>,
    ]);
    const pointsBySeq = new Map(tracks.map((t) => [t.seq, t.gpsPoints.map((p) => [p.lng, p.lat])]));
    const windows = session.windows.map((w) => ({ ...w, points: pointsBySeq.get(w.seq) ?? [] }));
    return { session: { ...session, windows }, user: user ?? null, auditLogs };
  }

  /**
   * Kết luận một nhật ký GIGO. `restoreSession` (chỉ với false_positive): Phiên chạy bị loại thành COMPLETED hợp lệ,
   * cộng bù km cho Sinh viên và Trường nếu Phiên bắt đầu trong Mùa giải đang mở. Đất không chiếm bù được.
   */
  review(adminId: string, logId: string, status: GigoReviewStatus, restoreSession = false) {
    if (restoreSession && status !== 'false_positive') {
      throw new BadRequestException({ code: 'HTTP_400', message: 'Chỉ khôi phục Phiên chạy khi kết luận báo nhầm.' });
    }
    return this.dataSource.transaction(async (tx) => {
      const log = await tx.findOne(GigoAuditLog, { where: { id: logId }, lock: { mode: 'pessimistic_write' } });
      if (!log) throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy nhật ký GIGO.' });

      const session = log.session_id
        ? await tx.findOne(RunningSession, { where: { id: log.session_id }, lock: { mode: 'pessimistic_write' } })
        : null;
      // Phiên đã khôi phục thì km đã cộng; kết luận gian lận lại sẽ lệch Quỹ Km, nên bắt admin xử lý tay.
      if (status === 'confirmed_cheat' && session && session.status !== 'REJECTED') {
        throw new ConflictException({
          code: 'ERR_108',
          message: 'Phiên chạy của nhật ký này đã được khôi phục thành hợp lệ, không thể kết luận gian lận.',
        });
      }

      await tx.update(GigoAuditLog, log.id, { review_status: status, reviewed_by: adminId, reviewed_at: new Date() });

      let restored: { addedKm: number; inCurrentSeason: boolean } | null = null;
      if (restoreSession && session?.status === 'REJECTED') {
        await tx.update(RunningSession, session.id, { status: 'COMPLETED', is_valid: true, rejection_reason: null });
        const seasonStart = await currentSeasonStart(tx);
        const inCurrentSeason = !!seasonStart && new Date(session.created_at) >= seasonStart;
        const km = inCurrentSeason ? session.distance_meters / 1000 : 0;
        if (km > 0) {
          await tx.increment(User, { id: session.user_id }, 'personal_km', km);
          const owner = await tx.findOne(User, { where: { id: session.user_id } });
          if (owner?.university_id) {
            await tx.increment(University, { id: owner.university_id }, 'total_season_km', km);
          }
        }
        restored = { addedKm: Number(km.toFixed(3)), inCurrentSeason };
      }

      await this.audit.log(tx, adminId, 'gigo.review', 'gigo_log', log.id, {
        from: log.review_status,
        to: status,
        sessionId: log.session_id,
        restored,
      });
      return { id: log.id, reviewStatus: status, restored };
    });
  }
}
