import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class LeaderboardService {
  constructor(private readonly dataSource: DataSource) {}

  /**
   * Bảng xếp hạng Sức mạnh Tổng hợp của một Cụm (bỏ trống = mọi Cụm, xếp theo Cụm rồi điểm).
   * Cụm chưa có Đấu trường (cluster_has_arena = false) tính 100% theo % Km.
   */
  async getLiveScores(cluster?: string) {
    return cluster
      ? this.dataSource.query(
          'SELECT * FROM v_campus_live_scores WHERE cluster_code = $1 ORDER BY composite_power_pct DESC, short_code',
          [cluster],
        )
      : this.dataSource.query('SELECT * FROM v_campus_live_scores ORDER BY cluster_code, composite_power_pct DESC, short_code');
  }

  /**
   * Mùa giải đang mở (số lớn nhất, như cron close_finished_season), hoặc null nếu không có.
   * ends_at = 00:00 ngày sau end_date giờ Việt Nam, tức hết ngày end_date.
   */
  async getActiveSeason() {
    const [season] = await this.dataSource.query(`
      SELECT season_number,
             to_char(start_date, 'YYYY-MM-DD') AS start_date,
             to_char(end_date, 'YYYY-MM-DD') AS end_date,
             ((end_date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh') AS ends_at
      FROM seasons
      WHERE is_active
      ORDER BY season_number DESC
      LIMIT 1
    `);
    return season ?? null;
  }

  /**
   * Lấy lịch sử Đại Sảnh Danh Vọng (Hall of Fame) các mùa giải trước
   */
  async getHallOfFame(cluster?: string) {
    return this.dataSource.query(
      `SELECT h.*, COALESCE(u.short_name, u.short_code) AS champion_name, u.short_code, u.hex_color
       FROM hall_of_fame h
       LEFT JOIN universities u ON h.champion_university_id = u.id
       WHERE $1::varchar IS NULL OR h.cluster_code = $1
       ORDER BY h.season_number DESC, h.cluster_code`,
      [cluster ?? null],
    );
  }
}
