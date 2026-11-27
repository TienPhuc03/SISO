import { DataSource } from 'typeorm';
import { LeaderboardService } from './leaderboard.service';

describe('LeaderboardService', () => {
  const setup = (query: jest.Mock) => new LeaderboardService({ query } as unknown as DataSource);

  it('trả bảng xếp hạng từ view, cao nhất trước', async () => {
    const rows = [{ short_code: 'UEF', composite_power_pct: 60 }];
    const query = jest.fn().mockResolvedValue(rows);

    await expect(setup(query).getLiveScores()).resolves.toBe(rows);
    expect(query.mock.calls[0][0]).toContain('v_campus_live_scores ORDER BY cluster_code, composite_power_pct DESC');
  });

  it('lọc theo Cụm bằng tham số, không ghép chuỗi', async () => {
    const query = jest.fn().mockResolvedValue([]);
    await setup(query).getLiveScores('NORTH');
    expect(query.mock.calls[0][0]).toContain('WHERE cluster_code = $1 ORDER BY composite_power_pct DESC');
    expect(query.mock.calls[0][1]).toEqual(['NORTH']);
  });

  it('Đại sảnh Danh vọng lọc theo Cụm', async () => {
    const query = jest.fn().mockResolvedValue([]);
    await setup(query).getHallOfFame('SOUTH');
    expect(query.mock.calls[0][1]).toEqual(['SOUTH']);
    await setup(query).getHallOfFame();
    expect(query.mock.calls[1][1]).toEqual([null]);
  });

  it('view lỗi thì báo lỗi, không trả bảng điểm 0 giả', async () => {
    const query = jest.fn().mockRejectedValue(new Error('relation does not exist'));

    await expect(setup(query).getLiveScores()).rejects.toThrow('relation does not exist');
    expect(query).toHaveBeenCalledTimes(1);
  });

  it('Mùa giải đang mở: lấy Mùa mở có số lớn nhất, hết hạn sau ngày end_date giờ VN', async () => {
    const row = { season_number: 2, end_date: '2026-11-30', ends_at: '2026-11-30T17:00:00.000Z' };
    const query = jest.fn().mockResolvedValue([row]);

    await expect(setup(query).getActiveSeason()).resolves.toBe(row);
    const sql = query.mock.calls[0][0];
    expect(sql).toContain('WHERE is_active');
    expect(sql).toContain('ORDER BY season_number DESC');
    expect(sql).toContain("(end_date + 1)::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh'");
  });

  it('không có Mùa giải mở thì trả null', async () => {
    await expect(setup(jest.fn().mockResolvedValue([])).getActiveSeason()).resolves.toBeNull();
  });

  it('Đại sảnh Danh vọng lỗi thì báo lỗi, không trả danh sách rỗng', async () => {
    const query = jest.fn().mockRejectedValue(new Error('db down'));

    await expect(setup(query).getHallOfFame()).rejects.toThrow('db down');
  });
});
