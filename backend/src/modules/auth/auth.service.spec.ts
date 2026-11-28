import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Repository } from 'typeorm';

import {
  AuthService,
  DEV_OTP,
  OTP_MAX_ATTEMPTS,
  OTP_RESEND_COOLDOWN_MS,
  OTP_TTL_MS,
} from './auth.service';
import { GoogleIdTokenVerifier } from './google-id-token.verifier';
import { InMemoryOtpStore } from './otp/otp-store';
import { MailService } from './mail/mail.service';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

const HUTECH = {
  id: '22222222-2222-4222-8222-222222222222',
  short_code: 'HUTECH',
  short_name: 'HUTECH',
  district: 'Bình Thạnh',
  name: 'ĐH Công Nghệ TP.HCM (HUTECH)',
  email_domain: 'hutech.edu.vn',
  hex_color: '#FFCC00',
} as University;

const HUTECH_VIEW = {
  id: HUTECH.id,
  shortCode: 'HUTECH',
  shortName: 'HUTECH',
  name: HUTECH.name,
  color: '#FFCC00',
  clusterCode: 'NORTH',
};

const EMAIL = 'nguyenvana@hutech.edu.vn';
const JWT_SECRET = 'test-secret';

/** Lấy body lỗi nghiệp vụ { code, message } từ exception Nest */
async function errorOf(promise: Promise<unknown>) {
  try {
    await promise;
  } catch (e) {
    return { type: e, body: (e as BadRequestException).getResponse() as { code: string; message: string } };
  }
  throw new Error('Expected promise to reject');
}

describe('AuthService', () => {
  let service: AuthService;
  let otpStore: InMemoryOtpStore;
  let mail: { devMode: boolean; sendOtp: jest.Mock };
  let users: Map<string, User>;
  let userRepo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock; manager: { query: jest.Mock } };
  let google: { verifiedEmail: jest.Mock };
  let jwt: JwtService;
  let now: number;

  beforeEach(() => {
    now = new Date('2026-11-05T08:00:00.000Z').getTime();
    jest.spyOn(Date, 'now').mockImplementation(() => now);

    users = new Map();
    userRepo = {
      findOne: jest.fn(async ({ where, relations }) => {
        const found = [...users.values()].find(
          (u) => (where.email ? u.email === where.email : u.id === where.id) && (!where.role || u.role === where.role),
        );
        if (!found) return null;
        return relations?.includes('university') && found.university_id === HUTECH.id
          ? { ...found, university: HUTECH }
          : { ...found };
      }),
      create: jest.fn((data) => ({ ...data })),
      save: jest.fn(async (u) => {
        const saved = { id: u.id ?? `user-${users.size + 1}`, ...u };
        users.set(saved.id, saved);
        return saved;
      }),
      // Mùa 3 đang mở, chưa chạy Phiên nào; HUTECH thuộc Cụm NORTH
      manager: {
        query: jest.fn(async (sql: string) =>
          sql.includes('FROM public.seasons')
            ? [{ season_number: 3, start_date: '2026-11-12' }]
            : sql.includes('running_sessions')
              ? [{ ran: false }]
              : [{ cluster_code: 'NORTH' }],
        ),
      },
    };
    google = { verifiedEmail: jest.fn() };
    otpStore = new InMemoryOtpStore();
    mail = { devMode: false, sendOtp: jest.fn().mockResolvedValue(undefined) };
    jwt = new JwtService({ secret: JWT_SECRET, signOptions: { expiresIn: '7d' } });

    service = new AuthService(
      userRepo as unknown as Repository<User>,
      jwt,
      mail as unknown as MailService,
      otpStore,
      google as unknown as GoogleIdTokenVerifier,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  /** OTP đang lưu cho email (để test nhập đúng mã) */
  const storedOtp = async (email = EMAIL) => (await otpStore.get(email))!.otp;

  describe('requestEmailLogin', () => {
    it('email mới: sinh OTP 6 số ngẫu nhiên, gửi mail, chưa có Trường', async () => {
      const res = await service.requestEmailLogin('  NguyenVanA@HUTECH.edu.vn ');

      const otp = await storedOtp();
      expect(otp).toMatch(/^\d{6}$/);
      expect(mail.sendOtp).toHaveBeenCalledWith(EMAIL, otp, 5);
      expect(res.success).toBe(true);
      expect(res.message).not.toContain(otp);
      expect(res.data).toEqual({
        email: EMAIL,
        expiresInSeconds: 300,
        resendAfterSeconds: 60,
        university: null,
      });
    });

    it('tài khoản đã có Trường: trả kèm Trường đó', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, university_id: HUTECH.id } as User);
      const res = await service.requestEmailLogin(EMAIL);
      expect(res.data!.university).toEqual(HUTECH_VIEW);
    });

    it('OTP_DEV_MODE: OTP cố định 123456 và message có gợi ý demo', async () => {
      mail.devMode = true;
      const res = await service.requestEmailLogin(EMAIL);
      expect(await storedOtp()).toBe(DEV_OTP);
      expect(res.message).toContain('Demo OTP: 123456');
    });

    it('email thường (gmail) cũng nhận được OTP', async () => {
      await service.requestEmailLogin('a@gmail.com');
      expect(mail.sendOtp).toHaveBeenCalledWith('a@gmail.com', expect.stringMatching(/^\d{6}$/), 5);
    });

    it('gửi lại trong 60s -> ERR_103 kèm số giây phải chờ', async () => {
      await service.requestEmailLogin(EMAIL);
      now += 20_000;
      const { body } = await errorOf(service.requestEmailLogin(EMAIL));
      expect(body.code).toBe('ERR_103');
      expect(body.message).toContain('40 giây');
      expect(mail.sendOtp).toHaveBeenCalledTimes(1);
    });

    it('sau 60s được gửi lại, mã mới thay mã cũ và reset số lần sai', async () => {
      await service.requestEmailLogin(EMAIL);
      await otpStore.set(EMAIL, { ...(await otpStore.get(EMAIL))!, attempts: 3 });
      now += OTP_RESEND_COOLDOWN_MS;
      await service.requestEmailLogin(EMAIL);
      expect((await otpStore.get(EMAIL))!.attempts).toBe(0);
      expect(mail.sendOtp).toHaveBeenCalledTimes(2);
    });

    it('gửi mail lỗi -> xoá OTP để người dùng gửi lại được ngay', async () => {
      mail.sendOtp.mockRejectedValueOnce(new Error('SMTP down'));
      await expect(service.requestEmailLogin(EMAIL)).rejects.toThrow('SMTP down');
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });
  });

  describe('verifyOtp', () => {
    it('OTP đúng: tạo user chưa có Trường, trả JWT hạn 7 ngày, OTP dùng 1 lần', async () => {
      await service.requestEmailLogin(EMAIL);
      const res = await service.verifyOtp(EMAIL, await storedOtp());

      const created = [...users.values()][0];
      expect(created).toMatchObject({ email: EMAIL, display_name: 'nguyenvana' });
      expect(created.university_id).toBeUndefined();
      expect(res.data!.user).toEqual({
        id: created.id,
        email: EMAIL,
        displayName: 'nguyenvana',
        role: 'user',
        university: null,
        canChangeUniversity: true,
        seasonNumber: 3,
      });

      const payload = jwt.verify(res.data!.accessToken, { secret: JWT_SECRET });
      expect(payload).toMatchObject({ sub: created.id, email: EMAIL });
      expect(payload.role).toBeUndefined();
      expect(payload.exp - payload.iat).toBe(7 * 24 * 60 * 60);
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });

    it('lỗi DB khi tạo user: giữ OTP để thử lại', async () => {
      await service.requestEmailLogin(EMAIL);
      const otp = await storedOtp();
      userRepo.save.mockRejectedValueOnce(new Error('db down'));

      await expect(service.verifyOtp(EMAIL, otp)).rejects.toThrow('db down');
      expect(await otpStore.get(EMAIL)).toBeDefined();
      expect((await service.verifyOtp(EMAIL, otp)).success).toBe(true);
    });

    it('user đã tồn tại: không tạo mới, giữ Trường đã chọn', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      await service.requestEmailLogin(EMAIL);
      const res = await service.verifyOtp(EMAIL, await storedOtp());
      expect(userRepo.create).not.toHaveBeenCalled();
      expect(res.data!.user).toMatchObject({ id: 'u1', university: { shortCode: 'HUTECH' } });
    });

    it('email viết hoa/khoảng trắng vẫn khớp OTP', async () => {
      await service.requestEmailLogin(EMAIL);
      const res = await service.verifyOtp(' NGUYENVANA@hutech.edu.vn', await storedOtp());
      expect(res.success).toBe(true);
    });

    it('chưa yêu cầu OTP -> ERR_102', async () => {
      const { body } = await errorOf(service.verifyOtp(EMAIL, '123456'));
      expect(body.code).toBe('ERR_102');
    });

    it('OTP hết hạn sau 5 phút -> ERR_102 và xoá mã', async () => {
      await service.requestEmailLogin(EMAIL);
      const otp = await storedOtp();
      now += OTP_TTL_MS;
      const { body } = await errorOf(service.verifyOtp(EMAIL, otp));
      expect(body.code).toBe('ERR_102');
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });

    it('OTP sai -> ERR_102 kèm số lần còn lại', async () => {
      mail.devMode = true;
      await service.requestEmailLogin(EMAIL);
      const { body } = await errorOf(service.verifyOtp(EMAIL, '000000'));
      expect(body.code).toBe('ERR_102');
      expect(body.message).toContain(`còn ${OTP_MAX_ATTEMPTS - 1} lần`);
    });

    it('sai 5 lần -> ERR_103, mã bị khoá, nhập đúng sau đó cũng không được', async () => {
      mail.devMode = true;
      await service.requestEmailLogin(EMAIL);
      for (let i = 1; i < OTP_MAX_ATTEMPTS; i++) {
        expect((await errorOf(service.verifyOtp(EMAIL, '000000'))).body.code).toBe('ERR_102');
      }
      expect((await errorOf(service.verifyOtp(EMAIL, '000000'))).body.code).toBe('ERR_103');
      expect((await errorOf(service.verifyOtp(EMAIL, DEV_OTP))).body.code).toBe('ERR_103');
      expect(users.size).toBe(0);
    });

    it('bị khoá rồi không được gửi lại mã ngay (vẫn chờ đủ 60s kể từ lần gửi)', async () => {
      mail.devMode = true;
      await service.requestEmailLogin(EMAIL);
      now += 10_000;
      for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
        await errorOf(service.verifyOtp(EMAIL, '000000'));
      }

      const { body } = await errorOf(service.requestEmailLogin(EMAIL));
      expect(body.code).toBe('ERR_103');
      expect(body.message).toContain('50 giây');

      now += 50_000;
      await service.requestEmailLogin(EMAIL);
      expect((await service.verifyOtp(EMAIL, DEV_OTP)).success).toBe(true);
    });
  });

  describe('admin dùng email ngoài trường', () => {
    const GMAIL = 'quantri@gmail.com';

    it('admin cấp sẵn: nhận OTP, đăng nhập được, không gắn Trường, không tạo user mới', async () => {
      users.set('a1', { id: 'a1', email: GMAIL, display_name: 'Quản trị', role: 'admin', university_id: null } as unknown as User);
      const sent = await service.requestEmailLogin(' QuanTri@Gmail.com ');
      expect(sent.data!.university).toBeNull();

      const res = await service.verifyOtp(GMAIL, await storedOtp(GMAIL));
      expect(res.data!.user).toMatchObject({ id: 'a1', email: GMAIL, displayName: 'Quản trị', role: 'admin', university: null });
      expect(users.size).toBe(1);
      expect(jwt.verify(res.data!.accessToken, { secret: JWT_SECRET })).toMatchObject({ sub: 'a1' });
    });

    it('getMe: admin và Sinh viên chưa chọn Trường đều hợp lệ, university = null', async () => {
      users.set('a1', { id: 'a1', email: GMAIL, display_name: 'Q', role: 'admin' } as User);
      users.set('u2', { id: 'u2', email: 'x@gmail.com', display_name: 'X', role: 'user' } as User);
      expect((await service.getMe('a1')).data!.user.university).toBeNull();
      expect((await service.getMe('u2')).data!.user.university).toBeNull();
    });
  });

  describe('loginWithGoogle', () => {
    it('email Google mới: tạo tài khoản chưa có Trường, trả JWT', async () => {
      google.verifiedEmail.mockResolvedValue('SV.Moi@Gmail.com');
      const res = await service.loginWithGoogle('id-token');

      expect(google.verifiedEmail).toHaveBeenCalledWith('id-token');
      expect(res.data!.user).toMatchObject({ email: 'sv.moi@gmail.com', university: null });
      expect(jwt.verify(res.data!.accessToken, { secret: JWT_SECRET })).toMatchObject({ email: 'sv.moi@gmail.com' });
    });

    it('cùng email đã đăng nhập bằng OTP: vào đúng tài khoản cũ, không tạo mới', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      google.verifiedEmail.mockResolvedValue(EMAIL);
      const res = await service.loginWithGoogle('id-token');

      expect(userRepo.create).not.toHaveBeenCalled();
      expect(res.data!.user).toMatchObject({ id: 'u1', university: { shortCode: 'HUTECH' } });
    });

    it('token Google sai: báo lỗi, không tạo user', async () => {
      google.verifiedEmail.mockRejectedValue(new UnauthorizedException({ code: 'ERR_111' }));
      await expect(service.loginWithGoogle('bad')).rejects.toBeInstanceOf(UnauthorizedException);
      expect(users.size).toBe(0);
    });
  });

  describe('getMe', () => {
    it('trả thông tin user và trường', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      const res = await service.getMe('u1');
      expect(res.data!.user).toMatchObject({ id: 'u1', email: EMAIL, university: { shortCode: 'HUTECH' } });
    });

    it('kèm token mới đủ 7 ngày để gia hạn phiên', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      const res = await service.getMe('u1');

      const payload = jwt.verify(res.data!.accessToken, { secret: JWT_SECRET });
      expect(payload).toMatchObject({ sub: 'u1', universityId: HUTECH.id });
      expect(payload.exp - payload.iat).toBe(7 * 24 * 60 * 60);
    });

    it('user không còn tồn tại -> 401', async () => {
      await expect(service.getMe('ghost')).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
