import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

const TZ = `'Asia/Ho_Chi_Minh'`;
/** 00:00 hôm nay theo giờ VN, dạng timestamptz. */
const TODAY_START = `(date_trunc('day', now() AT TIME ZONE ${TZ}) AT TIME ZONE ${TZ})`;
/** Phiên chạy bị kẹt: vẫn ACTIVE (chưa có finished_at) sau hơn 2 giờ. */
const STUCK_WHERE = `s.status = 'ACTIVE' AND s.finished_at IS NULL AND s.created_at < now() - interval '2 hours'`;

/** Thống kê cho trang Tổng quan; mọi tổng hợp làm bằng SQL, không kéo dữ liệu thô về. */
@Injectable()
export class StatsService {
  constructor(private readonly dataSource: DataSource) {}

  async overview() {
    const [row] = await this.dataSource.query(`
      SELECT
        (SELECT COUNT(DISTINCT user_id) FROM public.running_sessions WHERE created_at >= ${TODAY_START})::int AS dau,
        (SELECT COUNT(DISTINCT user_id) FROM public.running_sessions WHERE created_at >= now() - interval '7 days')::int AS wau,
        (SELECT COUNT(DISTINCT user_id) FROM public.running_sessions WHERE created_at >= now() - interval '30 days')::int AS mau,
        (SELECT COUNT(*) FROM public.users)::int AS "totalUsers",
        (SELECT COUNT(*) FROM public.users WHERE created_at >= ${TODAY_START})::int AS "newUsersToday",
        (SELECT COUNT(*) FROM public.users WHERE created_at >= now() - interval '7 days')::int AS "newUsers7d",
        (SELECT COUNT(*) FROM public.running_sessions WHERE created_at >= ${TODAY_START})::int AS "sessionsToday",
        (SELECT COUNT(*) FROM public.running_sessions WHERE created_at >= ${TODAY_START} AND status = 'REJECTED')::int AS "rejectedToday",
        (SELECT COUNT(*) FROM public.running_sessions s WHERE ${STUCK_WHERE})::int AS "stuckSessions",
        (SELECT COUNT(*) FROM public.gigo_audit_logs WHERE review_status = 'pending')::int AS "pendingReviews",
        (SELECT COUNT(*) FROM public.users WHERE banned_until > now())::int AS "bannedUsers"`);
    return row;
  }

  /** Số Phiên chạy theo giờ trong ngày (giờ VN, 0-23) gộp trong `days` ngày qua; giờ trống vẫn có dòng 0. */
  byHour(days: number) {
    return this.dataSource.query(
      `SELECT g.h AS hour, COUNT(s.id)::int AS sessions,
              COUNT(s.id) FILTER (WHERE s.status = 'REJECTED')::int AS rejected
       FROM generate_series(0, 23) AS g(h)
       LEFT JOIN public.running_sessions s
         ON s.created_at >= now() - make_interval(days => $1)
        AND extract(hour FROM s.created_at AT TIME ZONE ${TZ}) = g.h
       GROUP BY g.h ORDER BY g.h`,
      [days],
    );
  }

  /** Theo ngày (giờ VN): số Phiên, Phiên bị loại, Sinh viên có chạy (DAU), Sinh viên mới; ngày trống vẫn có dòng 0. */
  daily(days: number) {
    return this.dataSource.query(
      `WITH d AS (
         SELECT generate_series((now() AT TIME ZONE ${TZ})::date - ($1::int - 1), (now() AT TIME ZONE ${TZ})::date, interval '1 day')::date AS day
       ), s AS (
         SELECT (created_at AT TIME ZONE ${TZ})::date AS day, COUNT(*) AS sessions,
                COUNT(*) FILTER (WHERE status = 'REJECTED') AS rejected, COUNT(DISTINCT user_id) AS active
         FROM public.running_sessions WHERE created_at >= now() - make_interval(days => $1 + 1) GROUP BY 1
       ), u AS (
         SELECT (created_at AT TIME ZONE ${TZ})::date AS day, COUNT(*) AS n
         FROM public.users WHERE created_at >= now() - make_interval(days => $1 + 1) GROUP BY 1
       )
       SELECT to_char(d.day, 'YYYY-MM-DD') AS day, COALESCE(s.sessions, 0)::int AS sessions,
              COALESCE(s.rejected, 0)::int AS rejected, COALESCE(s.active, 0)::int AS "activeUsers",
              COALESCE(u.n, 0)::int AS "newUsers"
       FROM d LEFT JOIN s USING (day) LEFT JOIN u USING (day) ORDER BY d.day`,
      [days],
    );
  }

  stuckSessions() {
    return this.dataSource.query(`
      SELECT s.id AS "sessionId", s.session_type AS "sessionType", s.distance_meters AS "distanceMeters",
             s.created_at AS "startedAt", s.updated_at AS "lastWindowAt",
             u.id AS "userId", u.email, u.display_name AS "displayName",
             un.short_code AS "universityCode", un.hex_color AS "universityColor"
      FROM public.running_sessions s
      JOIN public.users u ON u.id = s.user_id
      LEFT JOIN public.universities un ON un.id = u.university_id
      WHERE ${STUCK_WHERE}
      ORDER BY s.created_at LIMIT 50`);
  }
}
