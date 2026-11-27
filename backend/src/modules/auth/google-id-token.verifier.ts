import { existsSync } from 'fs';
import { BadRequestException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';

/**
 * Kiểm tra Firebase ID token (app đăng nhập Google qua Firebase Auth) và trả email đã xác minh.
 * Dùng chung service account với FCM (GOOGLE_APPLICATION_CREDENTIALS); không đặt thì tắt đăng nhập Google.
 */
@Injectable()
export class GoogleIdTokenVerifier {
  constructor(private readonly config: ConfigService) {}

  async verifiedEmail(idToken: string): Promise<string> {
    const credentials = this.config.get<string>('GOOGLE_APPLICATION_CREDENTIALS');
    if (!credentials || !existsSync(credentials)) {
      throw new BadRequestException({ code: 'ERR_110', message: 'Máy chủ chưa bật đăng nhập Google.' });
    }
    // PushService có thể đã khởi tạo app mặc định: dùng lại, không tạo trùng
    const app = getApps()[0] ?? initializeApp({ credential: applicationDefault() });

    let decoded: { email?: string; email_verified?: boolean };
    try {
      decoded = await getAuth(app).verifyIdToken(idToken);
    } catch {
      throw new UnauthorizedException({ code: 'ERR_111', message: 'Phiên đăng nhập Google không hợp lệ. Vui lòng thử lại.' });
    }
    if (!decoded.email || !decoded.email_verified) {
      throw new UnauthorizedException({ code: 'ERR_111', message: 'Tài khoản Google chưa có email đã xác minh.' });
    }
    return decoded.email;
  }
}
