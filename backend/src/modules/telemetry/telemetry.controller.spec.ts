import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import * as request from 'supertest';
import { TelemetryController } from './telemetry.controller';
import { TelemetryService } from './telemetry.service';
import { IMU_WINDOW_SIZE } from './dto/telemetry-payload.dto';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';

describe('TelemetryController: truyền body thô để kiểm chữ ký', () => {
  let app: INestApplication;
  const verifyWindow = jest.fn().mockResolvedValue({ sessionId: 's' });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      controllers: [TelemetryController],
      providers: [{ provide: TelemetryService, useValue: { verifyWindow } }],
    })
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
});
