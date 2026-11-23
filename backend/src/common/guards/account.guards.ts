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
    .findOne({ where: { id: userId }, select: { id: true, role: true, banned_until: true } });
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

/** Đặt SAU JwtAuthGuard: chặn Sinh viên đang bị cấm gửi telemetry / kết thúc Phiên chạy. */
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
    return true;
  }
}
