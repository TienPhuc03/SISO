import { Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { UserAvatar } from '../../entities/user-avatar.entity';
import { AdminAuditService } from './admin-audit.service';
import { StudentQueryDto } from './dto/admin-catalog.dto';

/** Mẫu ILIKE an toàn: thoát %, _ và \ do người dùng gõ. */
export const likePattern = (q: string) => `%${q.trim().replace(/[\\%_]/g, (c) => `\\${c}`)}%`;

const STUDENT_COLUMNS = `
  u.id, u.email, u.display_name AS "displayName", u.role, u.banned_until AS "bannedUntil",
  u.personal_km AS "personalKm", u.created_at AS "createdAt",
  un.id AS "universityId", un.short_code AS "universityCode", un.hex_color AS "universityColor",
  (SELECT COUNT(*) FROM public.running_sessions s WHERE s.user_id = u.id)::int AS sessions,
  (SELECT COUNT(*) FROM public.gigo_audit_logs g WHERE g.user_id = u.id AND g.review_status <> 'false_positive')::int AS violations,
  (SELECT MAX(s.created_at) FROM public.running_sessions s WHERE s.user_id = u.id) AS "lastRunAt",
  EXISTS (SELECT 1 FROM public.user_avatars a WHERE a.user_id = u.id) AS "hasAvatar"`;

@Injectable()
export class StudentsService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly audit: AdminAuditService,
  ) {}

  async list(q: StudentQueryDto) {
    const params: unknown[] = [];
    const where: string[] = [];
    if (q.q?.trim()) {
      const p = params.push(likePattern(q.q));
      where.push(`(u.email ILIKE $${p} OR u.display_name ILIKE $${p})`);
    }
    if (q.universityId) where.push(`u.university_id = $${params.push(q.universityId)}`);
    if (q.status === 'banned') where.push(`u.banned_until > now()`);
    if (q.status === 'admin') where.push(`u.role = 'admin'`);
    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';
    const n = params.length;
    const [items, [{ total }]] = await Promise.all([
      this.dataSource.query(
        `SELECT ${STUDENT_COLUMNS} FROM public.users u LEFT JOIN public.universities un ON un.id = u.university_id
         ${whereSql} ORDER BY u.created_at DESC LIMIT $${n + 1} OFFSET $${n + 2}`,
        [...params, q.limit, (q.page - 1) * q.limit],
      ),
      this.dataSource.query(`SELECT COUNT(*)::int AS total FROM public.users u ${whereSql}`, params),
    ]);
    return { items, total, page: q.page, limit: q.limit };
  }

  async detail(id: string) {
    const [student] = await this.dataSource.query(
      `SELECT ${STUDENT_COLUMNS}, un.name AS "universityName",
         (SELECT COUNT(*) FROM public.running_sessions s WHERE s.user_id = u.id AND s.status = 'COMPLETED')::int AS "completedSessions",
         (SELECT COUNT(*) FROM public.running_sessions s WHERE s.user_id = u.id AND s.status = 'REJECTED')::int AS "rejectedSessions",
         (SELECT COALESCE(SUM(s.distance_meters), 0) FROM public.running_sessions s
           WHERE s.user_id = u.id AND s.status = 'COMPLETED')::float AS "completedMeters"
       FROM public.users u LEFT JOIN public.universities un ON un.id = u.university_id WHERE u.id = $1`,
      [id],
    );
    if (!student) throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy Sinh viên.' });
    return student;
  }

  async sessions(userId: string, page: number, limit: number) {
    const [items, [{ total }]] = await Promise.all([
      this.dataSource.query(
        `SELECT s.id AS "sessionId", s.status, s.session_type AS "sessionType", s.distance_meters AS "distanceMeters",
                s.duration_seconds AS "durationSeconds", s.hex_count AS "hexCount", s.rejection_reason AS "rejectionReason",
                s.created_at AS "startedAt", s.finished_at AS "finishedAt"
         FROM public.running_sessions s WHERE s.user_id = $1 ORDER BY s.created_at DESC LIMIT $2 OFFSET $3`,
        [userId, limit, (page - 1) * limit],
      ),
      this.dataSource.query(`SELECT COUNT(*)::int AS total FROM public.running_sessions WHERE user_id = $1`, [userId]),
    ]);
    return { items, total, page, limit };
  }

  /** Gỡ ảnh đại diện (vd. ảnh phản cảm); Sinh viên có thể tải ảnh mới. */
  removeAvatar(adminId: string, userId: string) {
    return this.dataSource.transaction(async (tx) => {
      const { affected } = await tx.delete(UserAvatar, { user_id: userId });
      if (!affected) throw new NotFoundException({ code: 'ERR_105', message: 'Sinh viên chưa có ảnh đại diện.' });
      await this.audit.log(tx, adminId, 'user.avatar_remove', 'user', userId);
      return { userId };
    });
  }
}
