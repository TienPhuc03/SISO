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
import { matchCampusDomain } from './campus-domain';
import { InMemoryOtpStore } from './otp/otp-store';
import { MailService } from './mail/mail.service';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

const HUTECH = {
  id: '22222222-2222-4222-8222-222222222222',
  short_code: 'HUTECH',
  name: 'ĐH Công Nghệ TP.HCM (HUTECH)',
  email_domain: 'hutech.edu.vn',
  hex_color: '#FFCC00',
} as University;

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

describe('campus-domain: matchCampusDomain', () => {
  it.each([
    ['a@hutech.edu.vn', 'hutech.edu.vn'],
    ['A@UEF.EDU.VN', 'uef.edu.vn'],
    ['  b@ut.edu.vn ', 'ut.edu.vn'],
    ['c@ftu.edu.vn', 'ftu.edu.vn'],
    ['d@hiu.vn', 'hiu.vn'],
    ['e@st.hutech.edu.vn', 'hutech.edu.vn'],
    ['f@student.uef.edu.vn', 'uef.edu.vn'],
  ])('%s -> %s', (email, expected) => {
    expect(matchCampusDomain(email)).toBe(expected);
  });

  it.each([
    'a@gmail.com',
    'a@hcmus.edu.vn',
    'a@fakehutech.edu.vn', // không phải subdomain, chỉ trùng đuôi chữ
    'a@hutech.edu.vn.evil.com',
    'a@ut.edu.vn@x.com',
    '@hutech.edu.vn',
    'hutech.edu.vn',
  ])('từ chối %s', (email) => {
    expect(matchCampusDomain(email)).toBeNull();
  });
});

describe('AuthService', () => {
  let service: AuthService;
  let otpStore: InMemoryOtpStore;
  let mail: { devMode: boolean; sendOtp: jest.Mock };
  let users: Map<string, User>;
  let userRepo: { findOne: jest.Mock; create: jest.Mock; save: jest.Mock };
  let uniRepo: { findOne: jest.Mock };
  let jwt: JwtService;
  let now: number;

  beforeEach(() => {
    now = new Date('2026-11-05T08:00:00.000Z').getTime();
    jest.spyOn(Date, 'now').mockImplementation(() => now);

    users = new Map();
    userRepo = {
      findOne: jest.fn(async ({ where, relations }) => {
        const found = [...users.values()].find((u) =>
          where.email ? u.email === where.email : u.id === where.id,
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
    };
    uniRepo = {
      findOne: jest.fn(async ({ where }) => (where.email_domain === HUTECH.email_domain ? HUTECH : null)),
    };
    otpStore = new InMemoryOtpStore();
    mail = { devMode: false, sendOtp: jest.fn().mockResolvedValue(undefined) };
    jwt = new JwtService({ secret: JWT_SECRET, signOptions: { expiresIn: '7d' } });

    service = new AuthService(
      userRepo as unknown as Repository<User>,
      uniRepo as unknown as Repository<University>,
      jwt,
      mail as unknown as MailService,
      otpStore,
    );
  });

  afterEach(() => jest.restoreAllMocks());

  /** OTP đang lưu cho email (để test nhập đúng mã) */
  const storedOtp = async (email = EMAIL) => (await otpStore.get(email))!.otp;

  describe('requestEduLogin', () => {
    it('email hợp lệ: sinh OTP 6 số ngẫu nhiên, gửi mail, trả về thông tin trường', async () => {
      const res = await service.requestEduLogin('  NguyenVanA@HUTECH.edu.vn ');

      const otp = await storedOtp();
      expect(otp).toMatch(/^\d{6}$/);
      expect(mail.sendOtp).toHaveBeenCalledWith(EMAIL, otp, 5);
      expect(res.success).toBe(true);
      expect(res.message).not.toContain(otp);
      expect(res.data).toEqual({
        email: EMAIL,
        expiresInSeconds: 300,
        resendAfterSeconds: 60,
        university: { id: HUTECH.id, shortCode: 'HUTECH', name: HUTECH.name, color: '#FFCC00' },
      });
    });

    it('OTP_DEV_MODE: OTP cố định 123456 và message có gợi ý demo', async () => {
      mail.devMode = true;
      const res = await service.requestEduLogin(EMAIL);
      expect(await storedOtp()).toBe(DEV_OTP);
      expect(res.message).toContain('Demo OTP: 123456');
    });

    it('chấp nhận subdomain của trường (st.hutech.edu.vn)', async () => {
      const res = await service.requestEduLogin('sv@st.hutech.edu.vn');
      expect(res.data!.university.shortCode).toBe('HUTECH');
    });

    it('email ngoài 5 trường -> ERR_101, không gửi mail', async () => {
      const { type, body } = await errorOf(service.requestEduLogin('a@gmail.com'));
      expect(type).toBeInstanceOf(BadRequestException);
      expect(body.code).toBe('ERR_101');
      expect(mail.sendOtp).not.toHaveBeenCalled();
    });

    it('domain hợp lệ nhưng DB thiếu trường -> ERR_101', async () => {
      const { body } = await errorOf(service.requestEduLogin('a@uef.edu.vn'));
      expect(body.code).toBe('ERR_101');
    });

    it('gửi lại trong 60s -> ERR_103 kèm số giây phải chờ', async () => {
      await service.requestEduLogin(EMAIL);
      now += 20_000;
      const { body } = await errorOf(service.requestEduLogin(EMAIL));
      expect(body.code).toBe('ERR_103');
      expect(body.message).toContain('40 giây');
      expect(mail.sendOtp).toHaveBeenCalledTimes(1);
    });

    it('sau 60s được gửi lại, mã mới thay mã cũ và reset số lần sai', async () => {
      await service.requestEduLogin(EMAIL);
      await otpStore.set(EMAIL, { ...(await otpStore.get(EMAIL))!, attempts: 3 });
      now += OTP_RESEND_COOLDOWN_MS;
      await service.requestEduLogin(EMAIL);
      expect((await otpStore.get(EMAIL))!.attempts).toBe(0);
      expect(mail.sendOtp).toHaveBeenCalledTimes(2);
    });

    it('gửi mail lỗi -> xoá OTP để người dùng gửi lại được ngay', async () => {
      mail.sendOtp.mockRejectedValueOnce(new Error('SMTP down'));
      await expect(service.requestEduLogin(EMAIL)).rejects.toThrow('SMTP down');
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });
  });

  describe('verifyOtp', () => {
    it('OTP đúng: tạo user gắn đúng trường, trả JWT hạn 7 ngày, OTP dùng 1 lần', async () => {
      await service.requestEduLogin(EMAIL);
      const res = await service.verifyOtp(EMAIL, await storedOtp());

      const created = [...users.values()][0];
      expect(created).toMatchObject({ email: EMAIL, display_name: 'nguyenvana', university_id: HUTECH.id });
      expect(res.data!.user).toEqual({
        id: created.id,
        email: EMAIL,
        displayName: 'nguyenvana',
        university: { id: HUTECH.id, shortCode: 'HUTECH', name: HUTECH.name, color: '#FFCC00' },
      });

      const payload = jwt.verify(res.data!.accessToken, { secret: JWT_SECRET });
      expect(payload).toMatchObject({
        sub: created.id,
        email: EMAIL,
        universityId: HUTECH.id,
        role: 'authenticated',
      });
      expect(payload.exp - payload.iat).toBe(7 * 24 * 60 * 60);
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });

    it('lỗi DB khi tạo user: giữ OTP để thử lại', async () => {
      await service.requestEduLogin(EMAIL);
      const otp = await storedOtp();
      userRepo.save.mockRejectedValueOnce(new Error('db down'));

      await expect(service.verifyOtp(EMAIL, otp)).rejects.toThrow('db down');
      expect(await otpStore.get(EMAIL)).toBeDefined();
      expect((await service.verifyOtp(EMAIL, otp)).success).toBe(true);
    });

    it('user đã tồn tại: không tạo mới', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      await service.requestEduLogin(EMAIL);
      const res = await service.verifyOtp(EMAIL, await storedOtp());
      expect(userRepo.create).not.toHaveBeenCalled();
      expect(res.data!.user.id).toBe('u1');
    });

    it('user cũ bị thiếu university_id (lỗi trước đây) được gán bù', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: null } as unknown as User);
      await service.requestEduLogin(EMAIL);
      await service.verifyOtp(EMAIL, await storedOtp());
      expect(users.get('u1')!.university_id).toBe(HUTECH.id);
    });

    it('email viết hoa/khoảng trắng vẫn khớp OTP', async () => {
      await service.requestEduLogin(EMAIL);
      const res = await service.verifyOtp(' NGUYENVANA@hutech.edu.vn', await storedOtp());
      expect(res.success).toBe(true);
    });

    it('chưa yêu cầu OTP -> ERR_102', async () => {
      const { body } = await errorOf(service.verifyOtp(EMAIL, '123456'));
      expect(body.code).toBe('ERR_102');
    });

    it('OTP hết hạn sau 5 phút -> ERR_102 và xoá mã', async () => {
      await service.requestEduLogin(EMAIL);
      const otp = await storedOtp();
      now += OTP_TTL_MS;
      const { body } = await errorOf(service.verifyOtp(EMAIL, otp));
      expect(body.code).toBe('ERR_102');
      expect(await otpStore.get(EMAIL)).toBeUndefined();
    });

    it('OTP sai -> ERR_102 kèm số lần còn lại', async () => {
      mail.devMode = true;
      await service.requestEduLogin(EMAIL);
      const { body } = await errorOf(service.verifyOtp(EMAIL, '000000'));
      expect(body.code).toBe('ERR_102');
      expect(body.message).toContain(`còn ${OTP_MAX_ATTEMPTS - 1} lần`);
    });

    it('sai 5 lần -> ERR_103, mã bị khoá, nhập đúng sau đó cũng không được', async () => {
      mail.devMode = true;
      await service.requestEduLogin(EMAIL);
      for (let i = 1; i < OTP_MAX_ATTEMPTS; i++) {
        expect((await errorOf(service.verifyOtp(EMAIL, '000000'))).body.code).toBe('ERR_102');
      }
      expect((await errorOf(service.verifyOtp(EMAIL, '000000'))).body.code).toBe('ERR_103');
      expect((await errorOf(service.verifyOtp(EMAIL, DEV_OTP))).body.code).toBe('ERR_103');
      expect(users.size).toBe(0);
    });

    it('bị khoá rồi không được gửi lại mã ngay (vẫn chờ đủ 60s kể từ lần gửi)', async () => {
      mail.devMode = true;
      await service.requestEduLogin(EMAIL);
      now += 10_000;
      for (let i = 0; i < OTP_MAX_ATTEMPTS; i++) {
        await errorOf(service.verifyOtp(EMAIL, '000000'));
      }

      const { body } = await errorOf(service.requestEduLogin(EMAIL));
      expect(body.code).toBe('ERR_103');
      expect(body.message).toContain('50 giây');

      now += 50_000;
      await service.requestEduLogin(EMAIL);
      expect((await service.verifyOtp(EMAIL, DEV_OTP)).success).toBe(true);
    });
  });

  describe('getMe', () => {
    it('trả thông tin user và trường', async () => {
      users.set('u1', { id: 'u1', email: EMAIL, display_name: 'A', university_id: HUTECH.id } as User);
      const res = await service.getMe('u1');
      expect(res.data!.user).toMatchObject({ id: 'u1', email: EMAIL, university: { shortCode: 'HUTECH' } });
    });

    it('user không còn tồn tại -> 401', async () => {
      await expect(service.getMe('ghost')).rejects.toBeInstanceOf(UnauthorizedException);
    });
  });
});
