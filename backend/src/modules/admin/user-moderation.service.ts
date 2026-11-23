import { BadRequestException, ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { RunningSession } from '../../entities/running-session.entity';
import { User } from '../../entities/user.entity';
import { AdminAuditService } from './admin-audit.service';

/** Khoá vĩnh viễn: TypeORM không đọc được 'infinity' của Postgres nên dùng năm 9999. */
export const PERMANENT_BAN = new Date('9999-12-31T00:00:00Z');

@Injectable()
export class UserModerationService {
  constructor(
    private readonly dataSource: DataSource,
    private readonly audit: AdminAuditService,
  ) {}

  /**
   * Khoá Sinh viên tới `until` (bỏ trống = vĩnh viễn). Các Phiên chạy đang ACTIVE bị loại luôn (ERR_106):
   * nếu để nguyên, cron finish_stale_sessions sẽ tự kết thúc và vẫn cộng km cho chúng.
   */
  ban(adminId: string, userId: string, until: Date | null, reason: string) {
    const bannedUntil = until ?? PERMANENT_BAN;
    if (bannedUntil <= new Date()) {
      throw new BadRequestException({ code: 'HTTP_400', message: 'Thời điểm hết khoá phải ở tương lai.' });
    }
    return this.dataSource.transaction(async (tx) => {
      const user = await tx.findOne(User, { where: { id: userId }, lock: { mode: 'pessimistic_write' } });
      if (!user) throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy người dùng.' });
      if (user.role === 'admin') {
        throw new ConflictException({ code: 'ERR_108', message: 'Không thể khoá tài khoản admin.' });
      }

      await tx.update(User, user.id, { banned_until: bannedUntil });
      const closed = await tx.update(
        RunningSession,
        { user_id: user.id, status: 'ACTIVE' },
        { status: 'REJECTED', is_valid: false, rejection_reason: 'ERR_106', finished_at: new Date() },
      );
      const rejectedSessions = closed.affected ?? 0;
      await this.audit.log(tx, adminId, 'user.ban', 'user', user.id, {
        until: bannedUntil.toISOString(),
        reason,
        rejectedSessions,
      });
      return { userId: user.id, bannedUntil, rejectedSessions };
    });
  }

  unban(adminId: string, userId: string) {
    return this.dataSource.transaction(async (tx) => {
      const user = await tx.findOne(User, { where: { id: userId }, lock: { mode: 'pessimistic_write' } });
      if (!user) throw new NotFoundException({ code: 'HTTP_404', message: 'Không tìm thấy người dùng.' });
      await tx.update(User, user.id, { banned_until: null });
      await this.audit.log(tx, adminId, 'user.unban', 'user', user.id, { previousUntil: user.banned_until });
      return { userId: user.id, bannedUntil: null };
    });
  }
}
