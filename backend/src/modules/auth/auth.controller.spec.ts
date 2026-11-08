import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { JwtModule, JwtService } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { getRepositoryToken } from '@nestjs/typeorm';
import { ThrottlerModule } from '@nestjs/throttler';
import * as request from 'supertest';

import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { MailService } from './mail/mail.service';
import { InMemoryOtpStore, OTP_STORE } from './otp/otp-store';
import {
  AUTH_THROTTLE_ERROR,
  AUTH_THROTTLE_TTL_MS,
  EDU_LOGIN_LIMIT_PER_MIN,
  VERIFY_OTP_LIMIT_PER_MIN,
} from './auth-throttle';
import { AllExceptionsFilter } from '../../common/filters/all-exceptions.filter';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';

const JWT_SECRET = 'controller-test-secret';
const HUTECH = {
  id: '22222222-2222-4222-8222-222222222222',
  short_code: 'HUTECH',
  name: 'HUTECH',
  email_domain: 'hutech.edu.vn',
  hex_color: '#FFCC00',
} as University;

/**
 * Test tầng HTTP: ValidationPipe (whitelist + forbidNonWhitelisted giống main.ts),
 * AllExceptionsFilter và JwtAuthGuard, với DB và mail được giả lập.
 */
/** Dựng app Nest giống main.ts (ValidationPipe + AllExceptionsFilter + ThrottlerGuard), DB/mail giả. */
async function buildApp(users: Map<string, User>) {
  const userRepo = {
    findOne: jest.fn(async ({ where }) => {
      const u = [...users.values()].find((x) => (where.email ? x.email === where.email : x.id === where.id));
      return u ? { ...u, university: HUTECH } : null;
    }),
    create: jest.fn((d) => ({ ...d })),
    save: jest.fn(async (u) => {
      const saved = { id: u.id ?? 'user-1', ...u };
      users.set(saved.id, saved);
      return saved;
    }),
  };
  const uniRepo = {
    findOne: jest.fn(async ({ where }) => (where.email_domain === 'hutech.edu.vn' ? HUTECH : null)),
  };

  const moduleRef = await Test.createTestingModule({
    imports: [
      PassportModule,
      JwtModule.register({ secret: JWT_SECRET, signOptions: { expiresIn: '7d' } }),
      ThrottlerModule.forRoot({
        throttlers: [{ name: 'default', ttl: AUTH_THROTTLE_TTL_MS, limit: 30 }],
        errorMessage: AUTH_THROTTLE_ERROR,
      }),
    ],
    controllers: [AuthController],
    providers: [
      AuthService,
      JwtStrategy,
      { provide: ConfigService, useValue: { getOrThrow: () => JWT_SECRET } },
      { provide: MailService, useValue: { devMode: true, sendOtp: jest.fn() } },
      { provide: OTP_STORE, useClass: InMemoryOtpStore },
      { provide: getRepositoryToken(User), useValue: userRepo },
      { provide: getRepositoryToken(University), useValue: uniRepo },
    ],
  }).compile();

  const app = moduleRef.createNestApplication();
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
  app.useGlobalFilters(new AllExceptionsFilter());
  await app.init();
  return { app, jwt: moduleRef.get(JwtService) };
}

describe('AuthController (HTTP)', () => {
  let app: INestApplication;
  let jwt: JwtService;
  const users = new Map<string, User>();

  beforeAll(async () => {
    ({ app, jwt } = await buildApp(users));
  });

  afterAll(() => app.close());

  it('luồng đầy đủ: edu-login -> verify-otp -> me', async () => {
    const login = await request(app.getHttpServer())
      .post('/api/v1/auth/edu-login')
      .send({ email: 'sv@hutech.edu.vn' })
      .expect(200);
    expect(login.body).toMatchObject({ success: true, data: { email: 'sv@hutech.edu.vn' } });

    const verify = await request(app.getHttpServer())
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'sv@hutech.edu.vn', otp: '123456' })
      .expect(200);
    const token = verify.body.data.accessToken;
    expect(typeof token).toBe('string');

    const me = await request(app.getHttpServer())
      .get('/api/v1/auth/me')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    expect(me.body.data.user).toMatchObject({ email: 'sv@hutech.edu.vn', university: { shortCode: 'HUTECH' } });
  });

  it('email ngoài trường -> 400 ERR_101 theo format lỗi chung', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/edu-login')
      .send({ email: 'a@gmail.com' })
      .expect(400);
    expect(res.body).toMatchObject({ success: false, code: 'ERR_101', path: '/api/v1/auth/edu-login' });
  });

  it('email sai định dạng -> 400 (ValidationPipe)', async () => {
    const res = await request(app.getHttpServer()).post('/api/v1/auth/edu-login').send({ email: 'abc' }).expect(400);
    expect(res.body.success).toBe(false);
  });

  it('trường lạ trong body -> 400 (forbidNonWhitelisted)', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/edu-login')
      .send({ email: 'x@hutech.edu.vn', role: 'admin' })
      .expect(400);
  });

  it.each(['12345', '1234567', 'abcdef', '12 456'])('OTP "%s" không phải 6 chữ số -> 400', async (otp) => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'sv@hutech.edu.vn', otp })
      .expect(400);
  });

  it('OTP sai -> 400 ERR_102', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/edu-login').send({ email: 'otp@hutech.edu.vn' }).expect(200);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'otp@hutech.edu.vn', otp: '000000' })
      .expect(400);
    expect(res.body.code).toBe('ERR_102');
  });

  it('/me không có token -> 401', async () => {
    await request(app.getHttpServer()).get('/api/v1/auth/me').expect(401);
  });

  it('/me token ký sai secret -> 401', async () => {
    const forged = jwt.sign({ sub: 'user-1' }, { secret: 'wrong' });
    await request(app.getHttpServer()).get('/api/v1/auth/me').set('Authorization', `Bearer ${forged}`).expect(401);
  });

  it('/me token hết hạn -> 401', async () => {
    const expired = jwt.sign({ sub: 'user-1' }, { expiresIn: -10 });
    await request(app.getHttpServer()).get('/api/v1/auth/me').set('Authorization', `Bearer ${expired}`).expect(401);
  });
});

describe('AuthController: giới hạn request theo IP', () => {
  let app: INestApplication;
  let jwt: JwtService;

  beforeEach(async () => {
    ({ app, jwt } = await buildApp(new Map()));
  });

  afterEach(() => app.close());

  it(`edu-login: quá ${EDU_LOGIN_LIMIT_PER_MIN} lần/phút từ 1 IP -> 429 kèm thông báo tiếng Việt`, async () => {
    for (let i = 0; i < EDU_LOGIN_LIMIT_PER_MIN; i++) {
      await request(app.getHttpServer())
        .post('/api/v1/auth/edu-login')
        .send({ email: `sv${i}@hutech.edu.vn` })
        .expect(200);
    }
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/edu-login')
      .send({ email: 'one-more@hutech.edu.vn' })
      .expect(429);
    expect(res.body).toMatchObject({ success: false, code: 'HTTP_429', message: AUTH_THROTTLE_ERROR });
  });

  it(`verify-otp: quá ${VERIFY_OTP_LIMIT_PER_MIN} lần/phút từ 1 IP -> 429`, async () => {
    for (let i = 0; i < VERIFY_OTP_LIMIT_PER_MIN; i++) {
      await request(app.getHttpServer())
        .post('/api/v1/auth/verify-otp')
        .send({ email: `x${i}@hutech.edu.vn`, otp: '000000' })
        .expect(400);
    }
    await request(app.getHttpServer())
      .post('/api/v1/auth/verify-otp')
      .send({ email: 'x@hutech.edu.vn', otp: '000000' })
      .expect(429);
  });

  it('/me không bị giới hạn', async () => {
    const token = jwt.sign({ sub: 'nobody' });
    for (let i = 0; i < 40; i++) {
      await request(app.getHttpServer()).get('/api/v1/auth/me').set('Authorization', `Bearer ${token}`).expect(401);
    }
  });
});
