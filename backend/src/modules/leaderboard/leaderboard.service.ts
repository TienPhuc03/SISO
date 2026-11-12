import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class LeaderboardService {
  constructor(private readonly dataSource: DataSource) {}

  /**
   * Tính toán và trả về Bảng xếp hạng Sức mạnh Tổng hợp (50% Đất + 50% Km)
   */
  async getLiveScores() {
    return this.dataSource.query('SELECT * FROM v_campus_live_scores ORDER BY composite_power_pct DESC');
  }

  /**
   * Lấy lịch sử Đại Sảnh Danh Vọng (Hall of Fame) các mùa giải trước
   */
  async getHallOfFame() {
    return this.dataSource.query(`
      SELECT h.*, u.name as champion_name, u.short_code, u.hex_color
      FROM hall_of_fame h
      LEFT JOIN universities u ON h.champion_university_id = u.id
      ORDER BY h.season_number DESC
    `);
  }
}
