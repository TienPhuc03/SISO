import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { ProfileController } from './profile.controller';
import { MAX_AVATAR_BYTES, ProfileService } from './profile.service';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

const USER = '11111111-1111-4111-8111-111111111111';
const JPEG = Buffer.from([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

describe('ProfileController', () => {
  let app: INestApplication;
  const service = {
    getProfile: jest.fn().mockResolvedValue({ id: USER }),
    updateDisplayName: jest.fn().mockResolvedValue({ id: USER }),
    setAvatar: jest.fn().mockResolvedValue({ id: USER }),
    getAvatar: jest.fn().mockResolvedValue({ image: JPEG, mimeType: 'image/jpeg' }),
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [ProfileController],
      providers: [{ provide: ProfileService, useValue: service }],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate: (ctx) => {
          ctx.switchToHttp().getRequest().user = { userId: USER };
          return true;
        },
      })
      .compile();
    // Cùng cấu hình với main.ts.
    app = moduleRef.createNestApplication({ rawBody: true });
    app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true, forbidNonWhitelisted: true }));
    await app.init();
  });

  afterAll(() => app.close());
  beforeEach(() => jest.clearAllMocks());

  describe('PATCH /profile: nickname', () => {
    it('bỏ khoảng trắng đầu/cuối rồi lưu cho chính người đang đăng nhập', async () => {
      await request(app.getHttpServer()).patch('/api/v1/profile').send({ displayName: '  Minh Chạy  ' }).expect(200);
      expect(service.updateDisplayName).toHaveBeenCalledWith(USER, 'Minh Chạy');
    });

    it.each([
      ['quá ngắn', 'A'],
      ['quá dài', 'x'.repeat(31)],
      ['chỉ có khoảng trắng', '     '],
      ['có xuống dòng', 'Minh\nChạy'],
    ])('%s → 400, không lưu', async (_name, displayName) => {
      await request(app.getHttpServer()).patch('/api/v1/profile').send({ displayName }).expect(400);
      expect(service.updateDisplayName).not.toHaveBeenCalled();
    });

    it('trường lạ → 400', async () => {
      await request(app.getHttpServer()).patch('/api/v1/profile').send({ displayName: 'Minh', email: 'x@y.z' }).expect(400);
    });
  });

  describe('PUT /profile/avatar', () => {
    it('chuyển byte file multipart cho service', async () => {
      await request(app.getHttpServer())
        .put('/api/v1/profile/avatar')
        .attach('file', JPEG, { filename: 'a.jpg', contentType: 'image/jpeg' })
        .expect(200);
      expect(service.setAvatar).toHaveBeenCalledWith(USER, JPEG);
    });

    it(`file lớn hơn ${MAX_AVATAR_BYTES} byte bị Multer chặn (413), không tới service`, async () => {
      await request(app.getHttpServer())
        .put('/api/v1/profile/avatar')
        .attach('file', Buffer.alloc(MAX_AVATAR_BYTES + 1), { filename: 'big.jpg', contentType: 'image/jpeg' })
        .expect(413);
      expect(service.setAvatar).not.toHaveBeenCalled();
    });
  });

  describe('GET /profile/avatar/:userId', () => {
    it('trả byte ảnh với đúng Content-Type và cache dài (URL có phiên bản)', async () => {
      const res = await request(app.getHttpServer()).get(`/api/v1/profile/avatar/${USER}`).expect(200);
      expect(res.headers['content-type']).toBe('image/jpeg');
      expect(res.headers['cache-control']).toContain('max-age=31536000');
      expect(Buffer.from(res.body)).toEqual(JPEG);
    });

    it('userId không phải UUID → 400', async () => {
      await request(app.getHttpServer()).get('/api/v1/profile/avatar/abc').expect(400);
      expect(service.getAvatar).not.toHaveBeenCalled();
    });
  });
});
