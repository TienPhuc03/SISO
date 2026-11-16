import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Repository } from 'typeorm';
import { TelemetryService } from './telemetry.service';
import { AntiGigoService } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { SCENARIOS } from './synthetic-imu.fixture';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';
import { ConfigService } from '@nestjs/config';
import { deriveSigningKey, signBody } from './telemetry-signature';

const USER = '11111111-1111-4111-8111-111111111111';
const SESSION = '22222222-2222-4222-8222-222222222222';
const SECRET = 'test-secret';

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
    last_window_seq: 0,
    is_valid: true,
    rejection_reason: null,
    hex_count: 0,
    ...overrides,
  } as RunningSession;
}

describe('TelemetryService: kiểm định Phiên chạy theo cửa sổ', () => {
  let service: TelemetryService;
  let sessions: {
    create: jest.Mock;
    save: jest.Mock;
    findOne: jest.Mock;
    manager: { transaction: jest.Mock };
  };
  let audits: { create: jest.Mock; save: jest.Mock };
  /** EntityManager giả trong transaction: verifyWindow dùng getRepository, finishSession dùng findOne/increment/update. */
  let tx: { getRepository: (entity: unknown) => unknown; findOne: jest.Mock; increment: jest.Mock; update: jest.Mock };
  let nextSeq: number;
  /** Kết cục của transaction gần nhất: commit (callback xong) hay rollback (callback ném lỗi). */
  let txOutcome: 'commit' | 'rollback' | null;

  /** Gửi như client thật: từ cửa sổ có sessionId trở đi thì ký nguyên văn body và tăng seq. */
  const verify = (dto: TelemetryPayloadDto) => {
    if (!dto.sessionId) return service.verifyWindow(USER, dto);
    const body = { seq: nextSeq++, ...dto };
    const rawBody = Buffer.from(JSON.stringify(body));
    const signature = signBody(deriveSigningKey(SECRET, dto.sessionId), rawBody);
    return service.verifyWindow(USER, body, { rawBody, signature });
  };

  beforeEach(() => {
    nextSeq = 1;
    sessions = {
      create: jest.fn((x) => ({ ...x })),
      save: jest.fn(async (x) => ({ id: x.id ?? SESSION, ...x })),
      findOne: jest.fn(),
      manager: { transaction: jest.fn() },
    };
    audits = { create: jest.fn((x) => x), save: jest.fn(async (x) => x) };
    txOutcome = null;
    tx = {
      getRepository: (entity: unknown) => (entity === RunningSession ? sessions : audits),
      findOne: jest.fn(),
      increment: jest.fn(),
      update: jest.fn(),
    };
    sessions.manager.transaction.mockImplementation(async (work: (m: typeof tx) => Promise<unknown>) => {
      try {
        const result = await work(tx);
        txOutcome = 'commit';
        return result;
      } catch (e) {
        txOutcome = 'rollback';
        throw e;
      }
    });
    service = new TelemetryService(
      new AntiGigoService(),
      sessions as unknown as Repository<RunningSession>,
      audits as unknown as Repository<GigoAuditLog>,
      { getOrThrow: () => SECRET } as unknown as ConfigService,
    );
  });

  it('cửa sổ đầu (không có sessionId) tạo Phiên chạy ACTIVE và trả sessionId', async () => {
    const res = await verify(payload());

    expect(sessions.create).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: USER, status: 'ACTIVE', session_type: 'FREE_RUN' }),
    );
    expect(res.sessionId).toBe(SESSION);
    expect(res.windowPassed).toBe(true);
    expect(res.cadenceSpm).toBeGreaterThan(150);
  });

  it('cửa sổ qua: cộng quãng đường và thời gian do server tính, xoá bộ đếm lỗi', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 1 }));

    const res = await verify(payload({ sessionId: SESSION }));

    const saved = sessions.save.mock.calls.at(-1)[0];
    expect(saved.distance_meters).toBeCloseTo(100 + 3.2 * 5.12, 1);
    expect(saved.duration_seconds).toBe(35);
    expect(res.consecutiveFailures).toBe(0);
  });

  it('chỉ tìm Phiên chạy của chính Sinh viên đang đăng nhập', async () => {
    sessions.findOne.mockResolvedValue(activeSession());

    await verify(payload({ sessionId: SESSION }));

    expect(sessions.findOne).toHaveBeenCalledWith(
      expect.objectContaining({ where: { id: SESSION, user_id: USER } }),
    );
  });

  it('khoá dòng Phiên chạy trong transaction: hai request cùng lúc không cùng lọt seq hay mất km', async () => {
    sessions.findOne.mockResolvedValue(activeSession());

    await verify(payload({ sessionId: SESSION }));

    expect(sessions.manager.transaction).toHaveBeenCalledTimes(1);
    expect(sessions.findOne).toHaveBeenCalledWith(
      expect.objectContaining({ lock: { mode: 'pessimistic_write' } }),
    );
    expect(txOutcome).toBe('commit');
  });

  it('bị loại trong transaction: vẫn commit trạng thái REJECTED và nhật ký GIGO rồi mới trả lỗi', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 1 }));

    await expect(
      verify(payload({ sessionId: SESSION, imuSamples: SCENARIOS.motorbike() })),
    ).rejects.toMatchObject({ response: { code: 'ERR_202' } });

    expect(txOutcome).toBe('commit');
    expect(sessions.save.mock.calls.at(-1)[0]).toMatchObject({ status: 'REJECTED' });
    expect(audits.save).toHaveBeenCalledTimes(1);
  });

  it('một cửa sổ nghi xe máy chỉ là cảnh báo: 200, windowPassed = false, chưa loại', async () => {
    sessions.findOne.mockResolvedValue(activeSession());

    const res = await verify(payload({ sessionId: SESSION, imuSamples: SCENARIOS.motorbike() }));

    expect(res.windowPassed).toBe(false);
    expect(res.consecutiveFailures).toBe(1);
    expect(sessions.save.mock.calls.at(-1)[0].status).toBe('ACTIVE');
    expect(audits.save).not.toHaveBeenCalled();
  });

  it('hai cửa sổ liên tiếp nghi xe máy: ERR_202, Phiên chạy REJECTED, ghi nhật ký GIGO', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ consecutive_biometric_failures: 1 }));

    await expect(
      verify(payload({ sessionId: SESSION, averageSpeedMps: 3.3, imuSamples: SCENARIOS.motorbike() })),
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

    const res = await verify(payload({ sessionId: SESSION, imuSamples: SCENARIOS.motorbike() }));

    expect(res.consecutiveFailures).toBe(1);
  });

  it('GPS giả bị loại ngay ở cửa sổ đầu tiên: ghi nhật ký GIGO, không tạo Phiên chạy', async () => {
    await expect(verify(payload({ isMocked: true }))).rejects.toMatchObject({
      response: { code: 'ERR_201' },
    });

    expect(sessions.save).not.toHaveBeenCalled();
    expect(audits.save).toHaveBeenCalledWith(
      expect.objectContaining({ user_id: USER, session_id: null, rejection_type: 'ERR_201', imu_cadence_spm: 0 }),
    );
  });

  it('cửa sổ đầu vượt tốc độ người: ERR_202, không tạo Phiên chạy', async () => {
    await expect(verify(payload({ averageSpeedMps: 12 }))).rejects.toMatchObject({
      response: { code: 'ERR_202' },
    });

    expect(sessions.save).not.toHaveBeenCalled();
    expect(audits.save).toHaveBeenCalledWith(expect.objectContaining({ session_id: null, rejection_type: 'ERR_202' }));
  });

  describe('ERR_203 (mất tín hiệu vệ tinh) chỉ bỏ cửa sổ, không loại Phiên', () => {
    it('cửa sổ đầu có sai số -1 (iOS chưa có tín hiệu): ERR_203, không tạo Phiên, không ghi nhật ký', async () => {
      await expect(verify(payload({ horizontalAccuracy: -1 }))).rejects.toMatchObject({
        response: { code: 'ERR_203' },
      });

      expect(sessions.save).not.toHaveBeenCalled();
      expect(audits.save).not.toHaveBeenCalled();
    });

    it('giữa Phiên chạy sai số > 20 m: ERR_203, Phiên vẫn ACTIVE và không cộng quãng đường', async () => {
      sessions.findOne.mockResolvedValue(activeSession());

      await expect(verify(payload({ sessionId: SESSION, horizontalAccuracy: 35 }))).rejects.toMatchObject({
        response: { code: 'ERR_203' },
      });

      expect(sessions.save).not.toHaveBeenCalled();
      expect(audits.save).not.toHaveBeenCalled();
    });
  });

  it('sessionId không tồn tại hoặc của Sinh viên khác: 404 ERR_204', async () => {
    sessions.findOne.mockResolvedValue(null);

    const call = verify(payload({ sessionId: SESSION }));

    await expect(call).rejects.toBeInstanceOf(NotFoundException);
    await expect(call).rejects.toMatchObject({ response: { code: 'ERR_204' } });
  });

  it('gửi tiếp vào Phiên chạy đã bị loại: 400 kèm mã đã loại, không kiểm định lại', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ status: 'REJECTED', rejection_reason: 'ERR_202' }));

    const call = verify(payload({ sessionId: SESSION }));

    await expect(call).rejects.toBeInstanceOf(BadRequestException);
    await expect(call).rejects.toMatchObject({ response: { code: 'ERR_202' } });
    expect(sessions.save).not.toHaveBeenCalled();
  });

  it('Phiên chạy đã kết thúc: 404 ERR_204', async () => {
    sessions.findOne.mockResolvedValue(activeSession({ status: 'COMPLETED' }));

    await expect(verify(payload({ sessionId: SESSION }))).rejects.toMatchObject({
      response: { code: 'ERR_204' },
    });
  });
  describe('chữ ký HMAC', () => {
    const signedBody = (seq: number) => {
      const dto = payload({ sessionId: SESSION, seq });
      const rawBody = Buffer.from(JSON.stringify(dto));
      return { dto, rawBody, signature: signBody(deriveSigningKey(SECRET, SESSION), rawBody) };
    };

    const expectRejected = async (call: Promise<unknown>) => {
      await expect(call).rejects.toMatchObject({ response: { code: 'ERR_205' } });
      expect(sessions.save).toHaveBeenCalledWith(
        expect.objectContaining({ status: 'REJECTED', rejection_reason: 'ERR_205' }),
      );
      expect(audits.save).toHaveBeenCalledWith(expect.objectContaining({ rejection_type: 'ERR_205' }));
    };

    it('cửa sổ đầu trả signingKey đúng của Phiên chạy, chưa cần ký', async () => {
      const res = await verify(payload());

      expect(res.signingKey).toBe(deriveSigningKey(SECRET, SESSION));
    });

    it('cửa sổ sau hợp lệ không trả lại khoá và lưu seq', async () => {
      sessions.findOne.mockResolvedValue(activeSession());
      const { dto, rawBody, signature } = signedBody(3);

      const res = await service.verifyWindow(USER, dto, { rawBody, signature });

      expect(res.signingKey).toBeUndefined();
      expect(sessions.save).toHaveBeenCalledWith(expect.objectContaining({ last_window_seq: 3 }));
    });

    it('body bị sửa: loại Phiên chạy với ERR_205', async () => {
      sessions.findOne.mockResolvedValue(activeSession());
      const { dto, signature } = signedBody(1);
      const tampered = Buffer.from(JSON.stringify({ ...dto, averageSpeedMps: 1 }));

      await expectRejected(service.verifyWindow(USER, dto, { rawBody: tampered, signature }));
    });

    it('thiếu chữ ký: loại Phiên chạy với ERR_205', async () => {
      sessions.findOne.mockResolvedValue(activeSession());

      await expectRejected(service.verifyWindow(USER, payload({ sessionId: SESSION, seq: 1 })));
    });

    it('thiếu seq: loại Phiên chạy với ERR_205', async () => {
      sessions.findOne.mockResolvedValue(activeSession());
      const dto = payload({ sessionId: SESSION });
      const rawBody = Buffer.from(JSON.stringify(dto));
      const signature = signBody(deriveSigningKey(SECRET, SESSION), rawBody);

      await expectRejected(service.verifyWindow(USER, dto, { rawBody, signature }));
    });

    it('gửi lại cửa sổ cũ (seq không tăng): loại Phiên chạy với ERR_205', async () => {
      sessions.findOne.mockResolvedValue(activeSession({ last_window_seq: 5 }));
      const { dto, rawBody, signature } = signedBody(5);

      await expectRejected(service.verifyWindow(USER, dto, { rawBody, signature }));
    });

    it('chữ ký của phiên khác không dùng được', async () => {
      sessions.findOne.mockResolvedValue(activeSession());
      const { dto, rawBody } = signedBody(1);
      const signature = signBody(deriveSigningKey(SECRET, 'phien-khac'), rawBody);

      await expectRejected(service.verifyWindow(USER, dto, { rawBody, signature }));
    });
  });

  describe('finishSession: kết thúc Phiên chạy tự do', () => {
    const UNI = '33333333-3333-4333-8333-333333333333';
    const givenSession = (session: RunningSession | null) =>
      tx.findOne.mockImplementation(async (entity) =>
        entity === RunningSession ? session : { id: USER, university_id: UNI },
      );

    it('cộng km đã kiểm định cho Sinh viên và trường, chuyển COMPLETED', async () => {
      givenSession(activeSession({ distance_meters: 2456 }));

      const res = await service.finishSession(USER, SESSION);

      expect(tx.findOne).toHaveBeenCalledWith(RunningSession, {
        where: { id: SESSION, user_id: USER },
        lock: { mode: 'pessimistic_write' },
      });
      expect(tx.increment).toHaveBeenCalledWith(User, { id: USER }, 'personal_km', 2.456);
      expect(tx.increment).toHaveBeenCalledWith(University, { id: UNI }, 'total_season_km', 2.456);
      expect(tx.update).toHaveBeenCalledWith(RunningSession, SESSION, { status: 'COMPLETED' });
      expect(res).toEqual({ sessionId: SESSION, distanceMeters: 2456, durationSeconds: 30, addedKm: 2.46 });
    });

    it('Phiên của người khác hoặc không tồn tại: 404 ERR_204, không cộng km', async () => {
      givenSession(null);

      await expect(service.finishSession(USER, SESSION)).rejects.toMatchObject({ response: { code: 'ERR_204' } });
      expect(tx.increment).not.toHaveBeenCalled();
    });

    it('kết thúc lần hai (đã COMPLETED): 404 ERR_204, không cộng km lần nữa', async () => {
      givenSession(activeSession({ status: 'COMPLETED' }));

      await expect(service.finishSession(USER, SESSION)).rejects.toMatchObject({ response: { code: 'ERR_204' } });
      expect(tx.increment).not.toHaveBeenCalled();
    });

    it('Phiên đã bị loại: 400 kèm mã lý do loại, không cộng km', async () => {
      givenSession(activeSession({ status: 'REJECTED', rejection_reason: 'ERR_202' }));

      await expect(service.finishSession(USER, SESSION)).rejects.toMatchObject({ response: { code: 'ERR_202' } });
      expect(tx.increment).not.toHaveBeenCalled();
    });
  });
});
