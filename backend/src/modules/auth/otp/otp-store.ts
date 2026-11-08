import { Injectable } from '@nestjs/common';

export interface OtpRecord {
  otp: string;
  /** Epoch ms OTP hết hạn */
  expiresAt: number;
  /** Số lần nhập sai đã dùng */
  attempts: number;
  /** Epoch ms lần gửi mã gần nhất (để chặn gửi lại quá nhanh) */
  lastSentAt: number;
}

/**
 * Nơi lưu OTP. Hiện dùng RAM (1 server); đổi sang Redis chỉ cần viết
 * class mới implement interface này rồi đổi provider trong AuthModule.
 */
export interface OtpStore {
  get(email: string): Promise<OtpRecord | undefined>;
  set(email: string, record: OtpRecord): Promise<void>;
  delete(email: string): Promise<void>;
}

export const OTP_STORE = Symbol('OTP_STORE');

@Injectable()
export class InMemoryOtpStore implements OtpStore {
  private readonly records = new Map<string, OtpRecord>();

  async get(email: string): Promise<OtpRecord | undefined> {
    return this.records.get(email);
  }

  async set(email: string, record: OtpRecord): Promise<void> {
    this.records.set(email, record);
  }

  async delete(email: string): Promise<void> {
    this.records.delete(email);
  }
}
