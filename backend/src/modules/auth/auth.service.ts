import {
  BadRequestException,
  Inject,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { JwtService } from '@nestjs/jwt';
import { Repository } from 'typeorm';
import { randomInt, timingSafeEqual } from 'crypto';

import { User, UserRole } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';
import { BaseResponseDto } from '../../common/dto/base-response.dto';
import { matchCampusDomain, normalizeEmail } from './campus-domain';
import { OTP_STORE, OtpStore } from './otp/otp-store';
import { MailService } from './mail/mail.service';

export const OTP_TTL_MS = 5 * 60 * 1000;
export const OTP_RESEND_COOLDOWN_MS = 60 * 1000;
export const OTP_MAX_ATTEMPTS = 5;
export const DEV_OTP = '123456';

export interface AuthUserView {
  id: string;
  email: string;
  displayName: string;
  role: UserRole;
  /** null = admin đăng nhập bằng email ngoài trường. */
  university: { id: string; shortCode: string; name: string; color: string } | null;
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(University)
    private readonly universityRepository: Repository<University>,
    private readonly jwtService: JwtService,
    private readonly mailService: MailService,
    @Inject(OTP_STORE) private readonly otpStore: OtpStore,
  ) {}

  /** Bước 1: kiểm tra email (đuôi email trường, hoặc admin đã được cấp sẵn), sinh OTP và gửi về hộp thư. */
  async requestEduLogin(rawEmail: string) {
    const email = normalizeEmail(rawEmail);
    const { university } = await this.resolveAccount(email);

    const now = Date.now();
    const existing = await this.otpStore.get(email);
    if (existing && now - existing.lastSentAt < OTP_RESEND_COOLDOWN_MS) {
      const waitSeconds = Math.ceil(
        (OTP_RESEND_COOLDOWN_MS - (now - existing.lastSentAt)) / 1000,
      );
      throw new BadRequestException({
        code: 'ERR_103',
        message: `Vui lòng đợi ${waitSeconds} giây trước khi gửi lại mã OTP.`,
      });
    }

    const otp = this.mailService.devMode ? DEV_OTP : this.generateOtp();
    await this.otpStore.set(email, {
      otp,
      expiresAt: now + OTP_TTL_MS,
      attempts: 0,
      lastSentAt: now,
    });

    try {
      await this.mailService.sendOtp(email, otp, OTP_TTL_MS / 60000);
    } catch (error) {
      await this.otpStore.delete(email);
      throw error;
    }

    const devHint = this.mailService.devMode ? ` (Demo OTP: ${DEV_OTP})` : '';
    return BaseResponseDto.ok(`Mã OTP đã được gửi về hộp thư ${email}${devHint}.`, {
      email,
      expiresInSeconds: OTP_TTL_MS / 1000,
      resendAfterSeconds: OTP_RESEND_COOLDOWN_MS / 1000,
      university: university ? this.toUniversityView(university) : null,
    });
  }

  /** Bước 2: xác thực OTP, tạo user nếu lần đầu, ký JWT (hạn theo JWT_EXPIRES_IN, mặc định 7 ngày). */
  async verifyOtp(rawEmail: string, rawOtp: string) {
    const email = normalizeEmail(rawEmail);
    const otp = rawOtp.trim();
    const record = await this.otpStore.get(email);

    if (!record || record.expiresAt <= Date.now()) {
      if (record) await this.otpStore.delete(email);
      throw new BadRequestException({
        code: 'ERR_102',
        message: 'Mã OTP không đúng hoặc đã hết hạn. Vui lòng gửi lại mã mới.',
      });
    }

    if (record.attempts >= OTP_MAX_ATTEMPTS) {
      throw this.otpLockedError();
    }

    if (!this.otpMatches(record.otp, otp)) {
      const attempts = record.attempts + 1;
      // Giữ record (không xoá) để lastSentAt vẫn chặn gửi lại mã mới trong 60s
      await this.otpStore.set(email, { ...record, attempts });
      if (attempts >= OTP_MAX_ATTEMPTS) {
        throw this.otpLockedError();
      }
      throw new BadRequestException({
        code: 'ERR_102',
        message: `Mã OTP không đúng. Bạn còn ${OTP_MAX_ATTEMPTS - attempts} lần thử.`,
      });
    }

    const { university, admin } = await this.resolveAccount(email);
    const user = admin ?? (await this.findOrCreateUser(email, university!));
    // Xoá OTP sau khi tạo/tìm user thành công: lỗi DB thì người dùng vẫn thử lại được bằng mã cũ
    await this.otpStore.delete(email);

    return BaseResponseDto.ok('Đăng nhập thành công.', {
      accessToken: this.signToken(user),
      user: this.toUserView(user, university),
    });
  }

  /**
   * Thông tin user của JWT hiện tại (AuthGate gọi khi mở app), kèm token mới để gia hạn phiên:
   * mở app thì token có lại đủ hạn, không hết hạn giữa chừng khi đang chạy rồi bị đá về Login.
   */
  async getMe(userId: string) {
    const user = await this.userRepository.findOne({
      where: { id: userId },
      relations: ['university'],
    });
    if (!user || (!user.university && user.role !== 'admin')) {
      throw new UnauthorizedException({
        code: 'HTTP_401',
        message: 'Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.',
      });
    }
    return BaseResponseDto.ok('Lấy thông tin tài khoản thành công.', {
      accessToken: this.signToken(user),
      user: this.toUserView(user, user.university ?? null),
    });
  }

  /** JWT hạn theo JWT_EXPIRES_IN (mặc định 7 ngày). */
  private signToken(user: User): string {
    return this.jwtService.sign({
      sub: user.id,
      email: user.email,
      universityId: user.university_id,
      // Không có claim `role`: token này không dùng được với Supabase REST dù JWT_SECRET có trùng.
      displayName: user.display_name,
    });
  }

  /**
   * Email trường -> Trường của nó (đuôi email đọc từ bảng universities, không ghi cứng).
   * Email khác chỉ hợp lệ khi đã có tài khoản role = 'admin' (cấp bằng SQL): không ai tự đăng ký bằng email thường được.
   */
  private async resolveAccount(email: string): Promise<{ university: University | null; admin?: User }> {
    const universities = await this.universityRepository.find();
    const domain = matchCampusDomain(email, universities.map((u) => u.email_domain));
    const university = universities.find((u) => u.email_domain === domain);
    if (university) return { university };

    const admin = await this.userRepository.findOne({ where: { email, role: 'admin' } });
    if (admin) return { university: null, admin };

    throw new BadRequestException({
      code: 'ERR_101',
      message: 'Email không thuộc trường đại học nào đang tham gia SISO.',
    });
  }

  private async findOrCreateUser(email: string, university: University): Promise<User> {
    const existing = await this.userRepository.findOne({ where: { email } });
    if (existing) {
      // User cũ bị tạo thiếu trường (lỗi trước đây) thì gán bù
      if (!existing.university_id) {
        existing.university_id = university.id;
        return this.userRepository.save(existing);
      }
      return existing;
    }
    const created = this.userRepository.create({
      email,
      display_name: email.split('@')[0].slice(0, 50),
      university_id: university.id,
    });
    return this.userRepository.save(created);
  }

  private otpLockedError() {
    return new BadRequestException({
      code: 'ERR_103',
      message: 'Bạn đã nhập sai OTP quá nhiều lần. Vui lòng gửi lại mã mới.',
    });
  }

  private generateOtp(): string {
    return randomInt(0, 1_000_000).toString().padStart(6, '0');
  }

  private otpMatches(expected: string, actual: string): boolean {
    const a = Buffer.from(expected);
    const b = Buffer.from(actual);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  private toUniversityView(university: University) {
    return {
      id: university.id,
      shortCode: university.short_code,
      name: university.name,
      color: university.hex_color,
    };
  }

  private toUserView(user: User, university: University | null): AuthUserView {
    return {
      id: user.id,
      email: user.email,
      displayName: user.display_name,
      role: user.role ?? 'user',
      university: university ? this.toUniversityView(university) : null,
    };
  }
}
