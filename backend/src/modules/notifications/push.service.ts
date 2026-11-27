import { existsSync } from 'fs';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, applicationDefault, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

/** Mỗi trường một topic FCM; app tự đăng ký topic của trường mình khi đăng nhập. GIỮ KHỚP với app. */
export const universityTopic = (universityId: string) => `university_${universityId}`;

/**
 * Gửi thông báo đẩy qua Firebase Cloud Messaging.
 * Không đặt GOOGLE_APPLICATION_CREDENTIALS (đường dẫn file service account) thì tắt, như OTP_DEV_MODE.
 */
@Injectable()
export class PushService {
  private readonly logger = new Logger(PushService.name);
  private readonly app?: App;

  constructor(config: ConfigService) {
    const credentials = config.get<string>('GOOGLE_APPLICATION_CREDENTIALS');
    if (!credentials) {
      this.logger.warn('Chưa đặt GOOGLE_APPLICATION_CREDENTIALS: tắt thông báo đẩy (FCM).');
      return;
    }
    // firebase-admin chỉ đọc file lúc gửi; kiểm tra sớm để báo lỗi ngay khi khởi động
    if (!existsSync(credentials)) {
      this.logger.error(`Không thấy file ${credentials} (GOOGLE_APPLICATION_CREDENTIALS): tắt thông báo đẩy.`);
      return;
    }
    // Đăng nhập Google (GoogleIdTokenVerifier) có thể đã khởi tạo app mặc định
    this.app = getApps()[0] ?? initializeApp({ credential: applicationDefault() });
  }

  get enabled(): boolean {
    return !!this.app;
  }

  async sendToTopic(topic: string, title: string, body: string, data: Record<string, string>) {
    if (!this.app) return;
    await getMessaging(this.app).send({
      topic,
      notification: { title, body },
      data,
      android: { priority: 'high' },
    });
  }
}
