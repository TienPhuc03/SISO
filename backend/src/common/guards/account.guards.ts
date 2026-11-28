import { CanActivate, ExecutionContext, ForbiddenException, Injectable } from '@nestjs/common';
import { DataSource } from 'typeorm';
import { User } from '../../entities/user.entity';

/** Đang bị cấm chơi tại thời điểm `now`. */
export function isBanned(user: Pick<User, 'banned_until'> | null, now = new Date()): boolean {
  return !!user?.banned_until && new Date(user.banned_until) > now;
}

/** Đọc role/banned_until từ DB mỗi request (JWT không có role), nên hạ quyền hay cấm có hiệu lực ngay. */
async function loadAccount(dataSource: DataSource, context: ExecutionContext) {
  const userId: string | undefined = context.switchToHttp().getRequest().user?.userId;
  if (!userId) return null;
  return dataSource
    .getRepository(User)
    .findOne({ where: { id: userId }, select: { id: true, role: true, banned_until: true, university_id: true } });
}

/** Đặt SAU JwtAuthGuard: chỉ cho user có role = 'admin'. */
@Injectable()
export class AdminGuard implements CanActivate {
  constructor(private readonly dataSource: DataSource) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const user = await loadAccount(this.dataSource, context);
    if (user?.role !== 'admin') {
      throw new ForbiddenException({ code: 'ERR_107', message: 'Tài khoản không có quyền quản trị.' });
    }
    return true;
  }
}

/**
 * Đặt SAU JwtAuthGuard: chặn gửi telemetry / kết thúc Phiên chạy / chiếm đất khi Sinh viên đang bị cấm (ERR_106)
 * hoặc chưa chọn Trường (ERR_109: km và Ô đất không có Trường nào để cộng).
 */
@Injectable()
export class NotBannedGuard implements CanActivate {
  constructor(private readonly dataSource: DataSource) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const user = await loadAccount(this.dataSource, context);
    if (isBanned(user)) {
      throw new ForbiddenException({
        code: 'ERR_106',
        message: `Tài khoản đang bị khoá đến ${new Date(user!.banned_until!).toLocaleString('vi-VN', {
          timeZone: 'Asia/Ho_Chi_Minh',
        })}.`,
      });
    }
    if (!user?.university_id) {
      throw new ForbiddenException({ code: 'ERR_109', message: 'Bạn cần chọn Trường trước (để chạy, đăng bài, tym, bình luận).' });
    }
    return true;
  }
}
