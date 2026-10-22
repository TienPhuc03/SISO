import { Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';

@Injectable()
export class LeaderboardService {
  constructor(private readonly dataSource: DataSource) {}

  /**
   * Tính toán và trả về Bảng xếp hạng Sức mạnh Tổng hợp (50% Đất + 50% Km)
   */
  async getLiveScores() {
    try {
      const scores = await this.dataSource.query('SELECT * FROM v_campus_live_scores ORDER BY composite_power_pct DESC');
      return scores;
    } catch {
      // Fallback nếu view chưa được tạo
      const unis = await this.dataSource.query('SELECT id, short_code, name, hex_color, total_season_km FROM universities');
      return unis.map((u: any) => ({
        university_id: u.id,
        short_code: u.short_code,
        name: u.name,
        hex_color: u.hex_color,
        total_season_km: u.total_season_km,
        territory_pct: 0.0,
        mileage_pct: 0.0,
        composite_power_pct: 0.0,
      }));
    }
  }

  /**
   * Lấy lịch sử Đại Sảnh Danh Vọng (Hall of Fame) các mùa giải trước
   */
  async getHallOfFame() {
    try {
      return await this.dataSource.query(`
        SELECT h.*, u.name as champion_name, u.short_code, u.hex_color 
        FROM hall_of_fame h
        LEFT JOIN universities u ON h.champion_university_id = u.id
        ORDER BY h.season_number DESC
      `);
    } catch {
      return [];
    }
  }
}
