import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';

const REQUIRED_SMTP_VARS = ['SMTP_HOST', 'SMTP_USER', 'SMTP_PASS'] as const;

/**
 * Gửi email OTP qua SMTP (mặc định Gmail + App Password).
 * Khi OTP_DEV_MODE=true thì không gửi mail, chỉ ghi log (OTP cố định 123456).
 */
@Injectable()
export class MailService {
  private readonly logger = new Logger(MailService.name);
  private readonly transporter?: nodemailer.Transporter;
  private readonly from: string;
  readonly devMode: boolean;

  constructor(config: ConfigService) {
    this.devMode = config.get<string>('OTP_DEV_MODE', 'false') === 'true';
    this.from = config.get<string>('MAIL_FROM') ?? config.get<string>('SMTP_USER') ?? '';

    if (this.devMode) {
      this.logger.warn('OTP_DEV_MODE=true: không gửi email, OTP cố định 123456.');
      return;
    }

    const missing = REQUIRED_SMTP_VARS.filter((key) => !config.get<string>(key));
    if (missing.length > 0) {
      throw new Error(
        `Thiếu cấu hình SMTP (${missing.join(', ')}) trong backend/.env. ` +
          'Điền SMTP_* để gửi OTP thật, hoặc đặt OTP_DEV_MODE=true khi dev/demo.',
      );
    }

    const port = Number(config.get<string>('SMTP_PORT', '465'));
    this.transporter = nodemailer.createTransport({
      host: config.get<string>('SMTP_HOST'),
      port,
      secure: port === 465,
      auth: {
        user: config.get<string>('SMTP_USER'),
        pass: config.get<string>('SMTP_PASS'),
      },
    });
  }

  async sendOtp(email: string, otp: string, ttlMinutes: number): Promise<void> {
    if (!this.transporter) {
      this.logger.log(`[DEV] OTP cho ${email}: ${otp}`);
      return;
    }

    await this.transporter.sendMail({
      from: this.from,
      to: email,
      subject: `[SISO] Mã xác thực đăng nhập: ${otp}`,
      text:
        `Mã OTP đăng nhập SISO của bạn là ${otp}.\n` +
        `Mã có hiệu lực trong ${ttlMinutes} phút. Không chia sẻ mã này cho bất kỳ ai.`,
      html:
        `<p>Mã OTP đăng nhập <b>SISO</b> của bạn là:</p>` +
        `<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${otp}</p>` +
        `<p>Mã có hiệu lực trong ${ttlMinutes} phút. Không chia sẻ mã này cho bất kỳ ai.</p>`,
    });
  }
}
