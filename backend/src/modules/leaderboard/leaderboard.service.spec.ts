import { DataSource } from 'typeorm';
import { LeaderboardService } from './leaderboard.service';

describe('LeaderboardService', () => {
  const setup = (query: jest.Mock) => new LeaderboardService({ query } as unknown as DataSource);

  it('trả bảng xếp hạng từ view, cao nhất trước', async () => {
    const rows = [{ short_code: 'UEF', composite_power_pct: 60 }];
    const query = jest.fn().mockResolvedValue(rows);

    await expect(setup(query).getLiveScores()).resolves.toBe(rows);
    expect(query.mock.calls[0][0]).toContain('v_campus_live_scores ORDER BY composite_power_pct DESC');
  });

  it('view lỗi thì báo lỗi, không trả bảng điểm 0 giả', async () => {
    const query = jest.fn().mockRejectedValue(new Error('relation does not exist'));

    await expect(setup(query).getLiveScores()).rejects.toThrow('relation does not exist');
    expect(query).toHaveBeenCalledTimes(1);
  });

  it('Đại sảnh Danh vọng lỗi thì báo lỗi, không trả danh sách rỗng', async () => {
    const query = jest.fn().mockRejectedValue(new Error('db down'));

    await expect(setup(query).getHallOfFame()).rejects.toThrow('db down');
  });
});
