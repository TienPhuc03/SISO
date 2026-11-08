import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Repository } from 'typeorm';
import { TelemetryService } from './telemetry.service';
import { AntiGigoService } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { SCENARIOS } from './synthetic-imu.fixture';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';

const USER = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';

function payload(overrides: Partial<TelemetryPayloadDto> = {}): TelemetryPayloadDto {
  return {
    averageSpeedMps: 3.2,
    horizontalAccuracy: 6,
    isMocked: false,
    imuSamples: SCENARIOS.running(),
    ...overrides,
  };
}

function activeSession(overrides: Partial<RunningSession> = {}): RunningSession {
  return {
    id: SESSION,
    user_id: USER,
    session_type: 'FREE_RUN',
    status: 'ACTIVE',
    distance_meters: 100,
    duration_seconds: 30,
    consecutive_biometric_failures: 0,
    is_valid: true,
    rejection_reason: null,
    hex_count: 0,
    ...overrides,
  } as RunningSession;
}

describe('TelemetryService: kiểm định Phiên chạy theo cửa sổ', () => {
  let service: TelemetryService;
  let sessions: { create: jest.Mock; save: jest.Mock; findOne: jest.Mock };
  let audits: { create: jest.Mock; save: jest.Mock };

  beforeEach(() => {
    sessions = {
      create: jest.fn((x) => ({ ...x })),
      save: jest.fn(async (x) => ({ id: x.id ?? SESSION, ...x })),
      findOne: jest.fn(),
    };
    audits = { create: jest.fn((x) => x), save: jest.fn(async (x) => x) };
    service = new TelemetryService(
      new AntiGigoService(),
      sessions as unknown as Repository<RunningSession>,
      audits as unknown as Repository<GigoAuditLog>,
    );
  });

  it('cửa sổ đầu (không có sessionId) tạo Phiên chạy ACTIVE và trả sessionId', async () => {
    const res = await service.verifyWindow(USER, payload());

    expect(sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: USER, status: 'ACTIVE', session_type: 'FREE_RUN' }),
    );
    expect(res.sessionId).toBe(SESSION);
    expect(res.windowPassed).toBe(true);
    expect(res.cadenceSpm).toBeGreaterThan(150);
  });

  it('cửa sổ qua: cộng quãng đường và thời gian do server tính, xoá bộ đếm lỗi', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 1 }));

    const res = await service.verifyWindow(USER, payload({ sessionId: SESSION }));

    const saved = sessions.save.mock.calls.at(-1)[0];
    expect(saved.distance_meters).toBeCloseTo(100 + 3.2 * 5.12, 1);
    expect(saved.duration_seconds).toBe(35);
    expect(res.consecutiveFailures).toBe(0);
  });

  it('chỉ tìm Phiên chạy của chính Sinh viên đang đăng nhập', async () => {
    sessions.findOne.mockResolvedValue(activeSession());

    await service.verifyWindow(USER, payload({ sessionId: SESSION }));

    expect(sessions.findOne).toHaveBeenCalledWith({ where: { id: SESSION, user_id: USER } });
  });

  it('một cửa sổ nghi xe máy chỉ là cảnh báo: 200, windowPassed = false, chưa loại', async () => {
    sessions.findOne.mockResolvedValue(activeSession());

    const res = await service.verifyWindow(USER, payload({ sessionId: SESSION, imuSamples: SCENARIOS.motorbike() }));

    expect(res.windowPassed).toBe(false);
    expect(res.consecutiveFailures).toBe(1);
    expect(sessions.save.mock.calls.at(-1)[0].status).toBe('ACTIVE');
    expect(audits.save).not.toHaveBeenCalled();
  });

  it('hai cửa sổ liên tiếp nghi xe máy: ERR_202, Phiên chạy REJECTED, ghi nhật ký GIGO', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 1 }));

    await expect(
      service.verifyWindow(USER, payload({ sessionId: SESSION, averageSpeedMps: 3.3, imuSamples: SCENARIOS.motorbike() })),
    ).rejects.toMatchObject({ response: { code: 'ERR_202' } });

    const saved = sessions.save.mock.calls.at(-1)[0];
    expect(saved).toMatchObject({ status: 'REJECTED', is_valid: false, rejection_reason: 'ERR_202' });
    expect(audits.save).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: USER,
        session_id: SESSION,
        rejection_type: 'ERR_202',
        raw_gps_speed_mps: 3.3,
        gps_accuracy_m: 6,
      }),
    );
    expect(audits.save.mock.calls[0][0].vertical_energy_g).toBeLessThan(0.2);
  });

  it('cửa sổ qua xen giữa thì đếm lại từ đầu (lỗi - qua - lỗi không bị loại)', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 0 }));

    const res = await service.verifyWindow(USER, payload({ sessionId: SESSION, imuSamples: SCENARIOS.motorbike() }));

    expect(res.consecutiveFailures).toBe(1);
  });

  it('GPS giả bị loại ngay ở cửa sổ đầu tiên, không chờ cửa sổ thứ hai', async () => {
    await expect(service.verifyWindow(USER, payload({ isMocked: true }))).rejects.toMatchObject({
      response: { code: 'ERR_201' },
    });

    expect(sessions.save.mock.calls.at(-1)[0]).toMatchObject({ status: 'REJECTED', rejection_reason: 'ERR_201' });
    expect(audits.save).toHaveBeenCalledWith(expect.objectContaining({ rejection_type: 'ERR_201', imu_cadence_spm: 0 }));
  });

  it('sessionId không tồn tại hoặc của Sinh viên khác: 404 ERR_204', async () => {
    sessions.findOne.mockResolvedValue(null);

    const call = service.verifyWindow(USER, payload({ sessionId: SESSION }));

    await expect(call).rejects.toBeInstanceOf(NotFoundException);
    await expect(call).rejects.toMatchObject({ response: { code: 'ERR_204' } });
  });

  it('gửi tiếp vào Phiên chạy đã bị loại: 400 kèm mã đã loại, không kiểm định lại', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ status: 'REJECTED', rejection_reason: 'ERR_202' }));

    const call = service.verifyWindow(USER, payload({ sessionId: SESSION }));

    await expect(call).rejects.toBeInstanceOf(BadRequestException);
    await expect(call).rejects.toMatchObject({ response: { code: 'ERR_202' } });
    expect(sessions.save).not.toHaveBeenCalled();
  });

  it('Phiên chạy đã kết thúc: 404 ERR_204', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ status: 'COMPLETED' }));

    await expect(service.verifyWindow(USER, payload({ sessionId: SESSION }))).rejects.toMatchObject({
      response: { code: 'ERR_204' },
    });
  });
});
