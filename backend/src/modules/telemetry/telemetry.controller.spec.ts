import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { TelemetryController } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';
import { IMU_WINDOW_SIZE } from './dto/telemetry-payload.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { NotBannedGuard } from '../../common/guards/account.guards';

describe('TelemetryController: truyền body thô để kiểm chữ ký', () => {
  let app: INestApplication;
  const verifyWindow = jest.fn().mockResolvedValue({ sessionId: 's' });
  const listSessions = jest.fn().mockResolvedValue([]);
  const getSession = jest.fn().mockResolvedValue({ sessionId: 's' });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [TelemetryController],
      providers: [{ provide: TelemetryService, useValue: { verifyWindow, listSessions, getSession } }],
    })
      .overrideGuard(NotBannedGuard)
      .useValue({ canActivate: () => true })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate: (ctx) => {
          ctx.switchToHttp().getRequest().user = { userId: 'u1' };
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

  it('service nhận đúng từng byte client gửi và chữ ký trong header', async () => {
    const samples = Array.from({ length: IMU_WINDOW_SIZE }, (_, i) => ({ ax: 1.0, ay: 0.5, az: 9.8, timestamp: i }));
    // Giữ nguyên "3.20": parse lại rồi in ra sẽ thành 3.2 và làm sai chữ ký nếu không dùng byte thô.
    const raw = `{"sessionId":"b5f67b4e-28c4-42b7-a35b-c2e3919e913a","seq":1,"averageSpeedMps":3.20,"horizontalAccuracy":6,"isMocked":false,"imuSamples":${JSON.stringify(samples)}}`;

    await request(app.getHttpServer())
      .post('/api/v1/telemetry/verify')
      .set('Content-Type', 'application/json')
      .set('X-Siso-Signature', 'abc123')
      .send(raw)
      .expect(200);

    const [userId, dto, proof] = verifyWindow.mock.calls[0];
    expect(userId).toBe('u1');
    expect(dto.seq).toBe(1);
    expect(proof.signature).toBe('abc123');
    expect(proof.rawBody.toString()).toBe(raw);
  });

  it('sai số GPS -1 của iOS qua được DTO để service trả ERR_203, không bị chặn thành HTTP_400', async () => {
    const samples = Array.from({ length: IMU_WINDOW_SIZE }, (_, i) => ({ ax: 0, ay: 0, az: 9.8, timestamp: i }));

    await request(app.getHttpServer())
      .post('/api/v1/telemetry/verify')
      .send({ averageSpeedMps: 0, horizontalAccuracy: -1, isMocked: false, imuSamples: samples })
      .expect(200);

    expect(verifyWindow.mock.calls.at(-1)[1].horizontalAccuracy).toBe(-1);
  });

  describe('gpsPoints: vệt GPS trong cửa sổ', () => {
    const samples = Array.from({ length: IMU_WINDOW_SIZE }, (_, i) => ({ ax: 0, ay: 0, az: 9.8, timestamp: i }));
    const point = { lat: 10.8, lng: 106.72, timestamp: 100, accuracy: 5 };
    const send = (gpsPoints: unknown) =>
      request(app.getHttpServer())
        .post('/api/v1/telemetry/verify')
        .send({ averageSpeedMps: 3, horizontalAccuracy: 5, isMocked: false, imuSamples: samples, gpsPoints });

    it('điểm hợp lệ tới service nguyên vẹn', async () => {
      await send([point, { ...point, timestamp: 1100 }]).expect(200);
      expect(verifyWindow.mock.calls.at(-1)[1].gpsPoints).toEqual([point, { ...point, timestamp: 1100 }]);
    });

    it('vĩ độ ngoài [-90, 90] hoặc kinh độ ngoài [-180, 180] → 400', async () => {
      await send([{ ...point, lat: 91 }]).expect(400);
      await send([{ ...point, lng: -181 }]).expect(400);
    });

    it('quá 20 điểm một cửa sổ → 400', async () => {
      await send(Array.from({ length: 21 }, () => point)).expect(400);
    });

    it('điểm thiếu trường hoặc có trường lạ → 400', async () => {
      const { accuracy, ...noAccuracy } = point;
      await send([noAccuracy]).expect(400);
      await send([{ ...point, altitude: 5 }]).expect(400);
    });
  });

  describe('Lịch sử Phiên chạy', () => {
    const SESSION = 'b5f67b4e-28c4-42b7-a35b-c2e3919e913a';

    it('mặc định trang 1, 20 dòng, của người đang đăng nhập', async () => {
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions').expect(200);
      expect(listSessions).toHaveBeenLastCalledWith('u1', 1, 20);
    });

    it('query dạng chuỗi được đổi sang số', async () => {
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions?page=2&limit=50').expect(200);
      expect(listSessions).toHaveBeenLastCalledWith('u1', 2, 50);
    });

    it('limit > 50, page < 1 hoặc không phải số → 400', async () => {
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions?limit=51').expect(400);
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions?page=0').expect(400);
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions?limit=abc').expect(400);
    });

    it('chi tiết: truyền sessionId và người đang đăng nhập', async () => {
      await request(app.getHttpServer()).get(`/api/v1/telemetry/sessions/${SESSION}`).expect(200);
      expect(getSession).toHaveBeenLastCalledWith('u1', SESSION);
    });

    it('chi tiết: id không phải UUID → 400, không gọi service', async () => {
      getSession.mockClear();
      await request(app.getHttpServer()).get('/api/v1/telemetry/sessions/abc').expect(400);
      expect(getSession).not.toHaveBeenCalled();
    });
  });
});
