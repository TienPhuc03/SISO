import { NotFoundException } from '@nestjs/common';
import { Repository } from 'typeorm';
import { ProfileService, MAX_AVATAR_BYTES } from './profile.service';
import { User } from '../../entities/user.entity';
import { UserAvatar } from '../../entities/user-avatar.entity';
import { RunningSession } from '../../entities/running-session.entity';

const USER = '11111111-1111-4111-8111-111111111111';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
const PNG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00]);
const WEBP = Buffer.concat([Buffer.from('RIFF'), Buffer.from([1, 2, 3, 4]), Buffer.from('WEBPVP8 ')]);

describe('ProfileService', () => {
  let users: { findOne: jest.Mock; update: jest.Mock };
  let avatars: { findOne: jest.Mock; upsert: jest.Mock };
  let sessions: { count: jest.Mock };
  let service: ProfileService;
  const updatedAt = new Date('2026-11-20T10:00:00.000Z');

  beforeEach(() => {
    users = {
      findOne: jest.fn().mockResolvedValue({
        id: USER,
        email: 'sv@ut.edu.vn',
        display_name: 'Minh',
        personal_km: 2.456,
        university: { id: 'uni', short_code: 'UTH', name: 'ĐH GTVT', hex_color: '#0B2545' },
      }),
      update: jest.fn(),
    };
    avatars = { findOne: jest.fn().mockResolvedValue(null), upsert: jest.fn() };
    sessions = { count: jest.fn().mockResolvedValue(4) };
    service = new ProfileService(
      users as unknown as Repository<User>,
      avatars as unknown as Repository<UserAvatar>,
      sessions as unknown as Repository<RunningSession>,
    );
  });

  describe('getProfile', () => {
    it('trả nickname, trường, Km cá nhân, số Phiên chạy hoàn thành; chưa có avatar thì avatarUrl null', async () => {
      const res = await service.getProfile(USER);

      expect(sessions.count).toHaveBeenCalledWith({ where: { user_id: USER, status: 'COMPLETED' } });
      expect(res).toEqual({
        id: USER,
        email: 'sv@ut.edu.vn',
        displayName: 'Minh',
        personalKm: 2.456,
        completedRuns: 4,
        avatarUrl: null,
        university: { shortCode: 'UTH', name: 'ĐH GTVT', color: '#0B2545' },
      });
    });

    it('có avatar: avatarUrl kèm phiên bản để ảnh mới không bị cache cũ che', async () => {
      avatars.findOne.mockResolvedValue({ updated_at: updatedAt });

      const res = await service.getProfile(USER);

      expect(avatars.findOne).toHaveBeenCalledWith({ where: { user_id: USER }, select: ['user_id', 'updated_at'] });
      expect(res.avatarUrl).toBe(`/api/v1/profile/avatar/${USER}?v=${updatedAt.getTime()}`);
    });

    it('Sinh viên không còn tồn tại: 404', async () => {
      users.findOne.mockResolvedValue(null);

      await expect(service.getProfile(USER)).rejects.toBeInstanceOf(NotFoundException);
    });
  });

  it('updateDisplayName: ghi nickname rồi trả hồ sơ mới', async () => {
    await service.updateDisplayName(USER, 'Minh Chạy');

    expect(users.update).toHaveBeenCalledWith({ id: USER }, { display_name: 'Minh Chạy' });
  });

  describe('setAvatar: chỉ nhận ảnh thật, nhỏ hơn giới hạn', () => {
    it.each([
      ['JPEG', JPEG, 'image/jpeg'],
      ['PNG', PNG, 'image/png'],
      ['WebP', WEBP, 'image/webp'],
    ])('%s: nhận diện theo byte đầu file, ghi đè avatar cũ', async (_name, bytes, mime) => {
      await service.setAvatar(USER, bytes);

      expect(avatars.upsert).toHaveBeenCalledWith(
        { user_id: USER, image: bytes, mime_type: mime, updated_at: expect.any(Date) },
        ['user_id'],
      );
    });

    it('file không phải ảnh (đổi đuôi .jpg cho file khác): 400 ERR_104, không ghi', async () => {
      await expect(service.setAvatar(USER, Buffer.from('<svg onload=alert(1)>'))).rejects.toMatchObject({
        status: 400,
        response: { code: 'ERR_104' },
      });
      expect(avatars.upsert).not.toHaveBeenCalled();
    });

    it('thiếu file hoặc file rỗng: 400 ERR_104', async () => {
      await expect(service.setAvatar(USER, undefined)).rejects.toMatchObject({ response: { code: 'ERR_104' } });
      await expect(service.setAvatar(USER, Buffer.alloc(0))).rejects.toMatchObject({ response: { code: 'ERR_104' } });
    });

    it(`lớn hơn ${MAX_AVATAR_BYTES} byte: 400 ERR_104`, async () => {
      const big = Buffer.concat([JPEG, Buffer.alloc(MAX_AVATAR_BYTES)]);

      await expect(service.setAvatar(USER, big)).rejects.toMatchObject({ response: { code: 'ERR_104' } });
      expect(avatars.upsert).not.toHaveBeenCalled();
    });
  });

  describe('getAvatar', () => {
    it('trả byte ảnh và kiểu MIME đã lưu', async () => {
      avatars.findOne.mockResolvedValue({ image: JPEG, mime_type: 'image/jpeg' });

      await expect(service.getAvatar(USER)).resolves.toEqual({ image: JPEG, mimeType: 'image/jpeg' });
    });

    it('chưa có avatar: 404 ERR_105', async () => {
      await expect(service.getAvatar(USER)).rejects.toMatchObject({ status: 404, response: { code: 'ERR_105' } });
    });
  });
});
