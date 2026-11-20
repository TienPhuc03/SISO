import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from '../../entities/user.entity';
import { UserAvatar } from '../../entities/user-avatar.entity';
import { RunningSession } from '../../entities/running-session.entity';
import { ProfileDto } from './dto/profile.dto';

/** Ảnh client đã thu nhỏ (512 px, JPEG) chỉ khoảng 50 KB; 512 KB là trần an toàn. */
export const MAX_AVATAR_BYTES = 512 * 1024;

/** Nhận diện ảnh theo byte đầu file: không tin tên file hay Content-Type client gửi. */
function sniffImageType(bytes: Buffer): string | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return 'image/jpeg';
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return 'image/png';
  }
  if (bytes.length >= 12 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/** Hồ sơ của chính Sinh viên: nickname, ảnh đại diện, Km cá nhân. */
@Injectable()
export class ProfileService {
  constructor(
    @InjectRepository(User)
    private readonly userRepository: Repository<User>,
    @InjectRepository(UserAvatar)
    private readonly avatarRepository: Repository<UserAvatar>,
    @InjectRepository(RunningSession)
    private readonly sessionRepository: Repository<RunningSession>,
  ) {}

  async getProfile(userId: string): Promise<ProfileDto> {
    const user = await this.userRepository.findOne({ where: { id: userId }, relations: ['university'] });
    if (!user) throw new NotFoundException({ code: 'ERR_204', message: 'Không tìm thấy Sinh viên.' });

    const [avatar, completedRuns] = await Promise.all([
      this.avatarRepository.findOne({ where: { user_id: userId }, select: ['user_id', 'updated_at'] }),
      this.sessionRepository.count({ where: { user_id: userId, status: 'COMPLETED' } }),
    ]);
    return {
      id: user.id,
      email: user.email,
      displayName: user.display_name ?? '',
      personalKm: user.personal_km,
      completedRuns,
      avatarUrl: avatar ? `/api/v1/profile/avatar/${user.id}?v=${avatar.updated_at.getTime()}` : null,
      university: user.university
        ? { shortCode: user.university.short_code, name: user.university.name, color: user.university.hex_color }
        : null,
    };
  }

  async updateDisplayName(userId: string, displayName: string): Promise<ProfileDto> {
    await this.userRepository.update({ id: userId }, { display_name: displayName });
    return this.getProfile(userId);
  }

  async setAvatar(userId: string, bytes: Buffer | undefined): Promise<ProfileDto> {
    const mimeType = bytes && bytes.length <= MAX_AVATAR_BYTES ? sniffImageType(bytes) : null;
    if (!bytes || !mimeType) {
      throw new BadRequestException({
        code: 'ERR_104',
        message: `AVATAR_INVALID: Ảnh đại diện phải là JPEG, PNG hoặc WebP, tối đa ${MAX_AVATAR_BYTES / 1024} KB.`,
      });
    }
    await this.avatarRepository.upsert(
      { user_id: userId, image: bytes, mime_type: mimeType, updated_at: new Date() },
      ['user_id'],
    );
    return this.getProfile(userId);
  }

  async getAvatar(userId: string): Promise<{ image: Buffer; mimeType: string }> {
    const avatar = await this.avatarRepository.findOne({ where: { user_id: userId } });
    if (!avatar) {
      throw new NotFoundException({ code: 'ERR_105', message: 'AVATAR_NOT_FOUND: Sinh viên chưa có ảnh đại diện.' });
    }
    return { image: avatar.image, mimeType: avatar.mime_type };
  }
}
