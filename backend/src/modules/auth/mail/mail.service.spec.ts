import { ConfigService } from '@nestjs/config';
import * as nodemailer from 'nodemailer';
import { MailService } from './mail.service';

jest.mock('nodemailer');

const configOf = (env: Record<string, string>) =>
  ({ get: (key: string, fallback?: string) => env[key] ?? fallback }) as unknown as ConfigService;

const SMTP_ENV = {
  SMTP_HOST: 'smtp.gmail.com',
  SMTP_PORT: '465',
  SMTP_USER: 'siso@gmail.com',
  SMTP_PASS: 'app-password',
  MAIL_FROM: 'SISO <siso@gmail.com>',
};

describe('MailService', () => {
  const sendMail = jest.fn().mockResolvedValue({});

  beforeEach(() => {
    jest.clearAllMocks();
    (nodemailer.createTransport as jest.Mock).mockReturnValue({ sendMail });
  });

  it('OTP_DEV_MODE=true: không tạo SMTP, không gửi mail', async () => {
    const service = new MailService(configOf({ OTP_DEV_MODE: 'true' }));
    await service.sendOtp('a@hutech.edu.vn', '123456', 5);
    expect(service.devMode).toBe(true);
    expect(nodemailer.createTransport).not.toHaveBeenCalled();
    expect(sendMail).not.toHaveBeenCalled();
  });

  it('không dev mode mà thiếu SMTP -> lỗi ngay khi khởi động, nêu tên biến thiếu', () => {
    expect(() => new MailService(configOf({ SMTP_HOST: 'smtp.gmail.com' }))).toThrow(
      /SMTP_USER, SMTP_PASS/,
    );
  });

  it('có SMTP: gửi mail chứa OTP tới đúng email', async () => {
    const service = new MailService(configOf(SMTP_ENV));
    await service.sendOtp('a@hutech.edu.vn', '482913', 5);

    expect(nodemailer.createTransport).toHaveBeenCalledWith(
      expect.objectContaining({ host: 'smtp.gmail.com', port: 465, secure: true }),
    );
    expect(sendMail).toHaveBeenCalledWith(
      expect.objectContaining({
        from: 'SISO <siso@gmail.com>',
        to: 'a@hutech.edu.vn',
        subject: expect.stringContaining('482913'),
        text: expect.stringContaining('5 phút'),
      }),
    );
  });
});
