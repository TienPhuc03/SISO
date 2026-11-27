import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export const FORUM_BUCKET = 'forum';

/**
 * Ảnh diễn đàn trên Supabase Storage (bucket public `forum`), gọi REST API bằng khoá bí mật của project:
 * khoá mới `sb_secret_...` (gửi qua header `apikey`) hoặc khoá `service_role` cũ dạng JWT (thêm `Authorization: Bearer`).
 * Thiếu SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY thì tắt: bài đăng chỉ có chữ (đăng ảnh báo ERR_114).
 */
@Injectable()
export class ForumImageStore {
  private readonly logger = new Logger(ForumImageStore.name);
  private readonly baseUrl?: string;
  private readonly key?: string;

  constructor(config: ConfigService) {
    this.baseUrl = config.get<string>('SUPABASE_URL')?.replace(/\/+$/, '');
    this.key = config.get<string>('SUPABASE_SERVICE_ROLE_KEY');
    if (!this.enabled) this.logger.warn('Chưa đặt SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY: diễn đàn không đăng được ảnh.');
  }

  /** Khoá mới không phải JWT nên không được gửi ở Authorization; gateway tự nhận quyền từ `apikey`. */
  private get authHeaders(): Record<string, string> {
    const key = this.key ?? '';
    return key.startsWith('eyJ') ? { apikey: key, Authorization: `Bearer ${key}` } : { apikey: key };
  }

  get enabled(): boolean {
    return !!this.baseUrl && !!this.key;
  }

  publicUrl(path: string): string {
    return `${this.baseUrl ?? ''}/storage/v1/object/public/${FORUM_BUCKET}/${path}`;
  }

  async upload(path: string, bytes: Buffer, mimeType: string): Promise<void> {
    if (!this.enabled) {
      throw new BadRequestException({ code: 'ERR_114', message: 'Máy chủ chưa bật lưu ảnh diễn đàn.' });
    }
    const res = await fetch(`${this.baseUrl}/storage/v1/object/${FORUM_BUCKET}/${path}`, {
      method: 'POST',
      headers: { ...this.authHeaders, 'Content-Type': mimeType, 'x-upsert': 'false' },
      body: new Uint8Array(bytes),
    });
    if (!res.ok) throw new Error(`Upload ảnh diễn đàn lỗi ${res.status}: ${await res.text()}`);
  }

  /** Xoá ảnh; lỗi chỉ ghi log (bài đã xoá trong DB, ảnh mồ côi không chặn người dùng). */
  async remove(paths: string[]): Promise<void> {
    if (!this.enabled || paths.length === 0) return;
    try {
      const res = await fetch(`${this.baseUrl}/storage/v1/object/${FORUM_BUCKET}`, {
        method: 'DELETE',
        headers: { ...this.authHeaders, 'Content-Type': 'application/json' },
        body: JSON.stringify({ prefixes: paths }),
      });
      if (!res.ok) this.logger.error(`Xoá ảnh diễn đàn lỗi ${res.status}: ${await res.text()}`);
    } catch (e) {
      this.logger.error(`Xoá ảnh diễn đàn lỗi: ${(e as Error).message}`);
    }
  }
}
