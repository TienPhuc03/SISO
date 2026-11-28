import { EntityManager } from 'typeorm';
import { User } from '../../entities/user.entity';

export interface UniversityChoice {
  /** Mùa giải đang mở; null nếu không có Mùa nào mở. */
  season: number | null;
  /** Lý do chưa được đổi Trường; null = được chọn / đổi ngay. */
  lockedReason: string | null;
}

/**
 * Luật khoá Trường theo Mùa giải:
 * - Chưa có Trường: chọn lúc nào cũng được; chọn xong khoá đến hết Mùa đó.
 * - Đã có Trường: chỉ đổi được ở Mùa sau Mùa đã chọn, và chỉ trước Phiên chạy hợp lệ đầu tiên của Mùa hiện tại.
 */
export async function universityChoice(
  m: EntityManager,
  user: Pick<User, 'id' | 'university_id' | 'university_season'>,
): Promise<UniversityChoice> {
  const [active] = await m.query(
    `SELECT season_number, to_char(start_date, 'YYYY-MM-DD') AS start_date
     FROM public.seasons WHERE is_active ORDER BY season_number DESC LIMIT 1`,
  );
  const season: number | null = active?.season_number ?? null;
  if (!user.university_id || season === null) return { season, lockedReason: null };

  const next = `đổi được khi Mùa ${season + 1} bắt đầu`;
  if (user.university_season === season) {
    return { season, lockedReason: `Bạn đã chọn Trường trong Mùa ${season}; ${next}.` };
  }
  const [{ ran }] = await m.query(
    `SELECT EXISTS (
       SELECT 1 FROM public.running_sessions
       WHERE user_id = $1 AND status = 'COMPLETED' AND is_valid
         AND created_at >= ($2::date::timestamp AT TIME ZONE 'Asia/Ho_Chi_Minh')
     ) AS ran`,
    [user.id, active.start_date],
  );
  return { season, lockedReason: ran ? `Bạn đã chạy cho Trường hiện tại trong Mùa ${season}; ${next}.` : null };
}
