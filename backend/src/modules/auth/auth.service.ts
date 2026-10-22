import { Injectable, BadRequestException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { JwtService } from '@nestjs/jwt';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

@Injectable()
export class AuthService {
  // Danh sách các domain email hợp lệ của 5 trường Bình Thạnh
  private readonly validDomains = [
    'hutech.edu.vn',
    'uef.edu.vn',
    'ut.edu.vn',
    'ftu.edu.vn',
    'hiu.vn',
  ];

  // Lưu tạm OTP trong bộ nhớ (trong môi trường thật sẽ lưu Redis)
  private readonly otpStore = new Map<string, { otp: string; expiresAt: number }>();

  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(University)
    private readonly universityRepository: Repository<University>,
    private readonly jwtService: JwtService,
  ) {}

  async requestEduLogin(email: string) {
    const parts = email.trim().toLowerCase().split('@');
    if (parts.length !== 2) {
      throw new BadRequestException({
        code: 'ERR_101',
        message: 'Định dạng email không hợp lệ.',
      });
    }

    const domain = parts[1];
    if (!this.validDomains.includes(domain)) {
      throw new BadRequestException({
        code: 'ERR_101',
        message: 'Email không thuộc danh sách trường đại học hợp lệ tại Bình Thạnh (HUTECH, UEF, UTH, FTU2, HIU).',
      });
    }

    const university = await this.universityRepository.findOne({
      where: { email_domain: domain },
    });

    if (!university) {
      throw new BadRequestException({
        code: 'ERR_101',
        message: 'Không tìm thấy trường đại học tương ứng trong hệ thống.',
      });
    }

    // Tạo mã OTP 6 số (mặc định demo là 123456)
    const otp = '123456';
    const expiresAt = Date.now() + 5 * 60 * 1000; // Hết hạn sau 5 phút
    this.otpStore.set(email.toLowerCase(), { otp, expiresAt });

    return {
      success: true,
      message: `Mã OTP xác thực đã được gửi về hộp thư ${email} (Demo OTP: 123456)`,
      university: {
        id: university.id,
        shortCode: university.short_code,
        name: university.name,
        color: university.hex_color,
      },
    };
  }

  async verifyOtp(email: string, otp: string) {
    const record = this.otpStore.get(email.toLowerCase());
    if (!record || record.otp !== otp || record.expiresAt < Date.now()) {
      throw new BadRequestException({
        code: 'ERR_AUTH_OTP_INVALID',
        message: 'Mã OTP không đúng hoặc đã hết hạn.',
      });
    }

    // Xóa OTP sau khi sử dụng
    this.otpStore.delete(email.toLowerCase());

    const domain = email.split('@')[1].toLowerCase();
    const university = await this.universityRepository.findOne({
      where: { email_domain: domain },
    });

    let user = await this.userRepository.findOne({
      where: { email: email.toLowerCase() },
      relations: ['university'],
    });

    if (!user) {
      user = this.userRepository.create({
        email: email.toLowerCase(),
        university_id: university?.id,
        display_name: email.split('@')[0],
      });
      user = await this.userRepository.save(user);
    }

    const payload = {
      sub: user.id,
      email: user.email,
      universityId: user.university_id,
    };

    const accessToken = this.jwtService.sign(payload);

    return {
      accessToken,
      user: {
        id: user.id,
        email: user.email,
        displayName: user.display_name,
        university: university
          ? {
              id: university.id,
              shortCode: university.short_code,
              name: university.name,
              color: university.hex_color,
            }
          : null,
      },
    };
  }
}
