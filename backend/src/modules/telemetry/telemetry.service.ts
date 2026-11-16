import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AntiGigoService, BiometricCheckResult } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResultDto } from './dto/verify-window-response.dto';
import { FinishSessionResultDto } from './dto/finish-session.dto';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';
import { deriveSigningKey, isValidSignature } from './telemetry-signature';

/** Bằng chứng toàn vẹn của một request: nguyên văn body và chữ ký trong header. */
export interface WindowProof {
  rawBody?: Buffer;
  signature?: string;
}

/** Số cửa sổ liên tiếp không qua Cổng Sinh trắc thì Phiên chạy bị loại. */
export const MAX_CONSECUTIVE_BIOMETRIC_FAILURES = 2;

/**
 * Kiểm định Phiên chạy theo từng cửa sổ 256 mẫu (Module 4).
 *
 * - Cửa sổ đầu tiên (không có sessionId) qua Cổng Động học thì tạo Phiên chạy ACTIVE và trả sessionId.
 * - Cổng Động học không qua: loại ngay, trừ ERR_203 (mất tín hiệu) chỉ bỏ cửa sổ đó.
 * - Cổng Sinh trắc không qua: chỉ loại khi đủ 2 cửa sổ liên tiếp; một cửa sổ lẻ chỉ cảnh báo.
 * - Mỗi lần loại: Phiên chạy chuyển REJECTED và ghi một dòng gigo_audit_logs.
 */
@Injectable()
export class TelemetryService {
  constructor(
    private readonly antiGigoService: AntiGigoService,
    @InjectRepository(RunningSession)
    private readonly sessionRepository: Repository<RunningSession>,
    @InjectRepository(GigoAuditLog)
    private readonly auditRepository: Repository<GigoAuditLog>,
    private readonly config: ConfigService,
  ) {}

  async verifyWindow(
    userId: string,
    dto: TelemetryPayloadDto,
    proof?: WindowProof,
  ): Promise<VerifyWindowResultDto> {
    // Cửa sổ đầu (không có sessionId) chỉ tạo Phiên chạy sau khi qua Cổng Động học.
    const existing = dto.sessionId ? await this.loadActiveSession(userId, dto.sessionId) : null;

    // Cửa sổ đầu chưa có khoá nên chưa ký được; mọi cửa sổ sau bắt buộc ký.
    if (existing) await this.assertAuthentic(existing, dto, proof);

    // Tầng 1: Cổng Động học (DEV 1). Không cho bỏ qua lần nào.
    const kinematic = this.antiGigoService.validateKinematics(
      dto.averageSpeedMps,
      dto.horizontalAccuracy,
      dto.isMocked,
    );
    if (!kinematic.isValid) {
      // ERR_203 là mất tín hiệu tạm thời (SRS: tạm dừng đo): bỏ cửa sổ này, giữ Phiên chạy.
      if (kinematic.errorCode !== 'ERR_203') {
        await this.rejectSession(userId, existing, kinematic.errorCode, dto, null);
      }
      throw new BadRequestException({ code: kinematic.errorCode, message: kinematic.message });
    }

    const session =
      existing ??
      this.sessionRepository.create({
        user_id: userId,
        session_type: 'FREE_RUN',
        status: 'ACTIVE',
        distance_meters: 0,
        duration_seconds: 0,
        consecutive_biometric_failures: 0,
        is_valid: true,
      });

    // Tầng 2: Cổng Sinh trắc. Một cửa sổ lẻ không qua chỉ là cảnh báo.
    const biometric = this.antiGigoService.validateBiometrics(dto.averageSpeedMps, dto.imuSamples);
    session.consecutive_biometric_failures = biometric.isValid
      ? 0
      : session.consecutive_biometric_failures + 1;

    if (session.consecutive_biometric_failures >= MAX_CONSECUTIVE_BIOMETRIC_FAILURES) {
      await this.rejectSession(userId, session, 'ERR_202', dto, biometric);
      throw new BadRequestException({ code: 'ERR_202', message: biometric.message });
    }

    // Server tự cộng quãng đường và thời gian (hợp đồng #3: không tin km do client tự báo).
    const { windowSeconds } = biometric.analysis;
    session.distance_meters = session.distance_meters + dto.averageSpeedMps * windowSeconds;
    session.duration_seconds = Math.round(session.duration_seconds + windowSeconds);
    const saved = await this.sessionRepository.save(session);

    return {
      ...this.toResult(saved, biometric),
      ...(existing ? {} : { signingKey: this.signingKeyOf(saved.id) }),
    };
  }

  /**
   * Kết thúc Phiên chạy không khép vòng (chạy tự do): cộng km đã kiểm định cho Sinh viên và trường.
   * Khoá dòng như claim-loop; ACTIVE → COMPLETED chỉ xảy ra một lần nên km không bị cộng hai lần.
   */
  async finishSession(userId: string, sessionId: string): Promise<FinishSessionResultDto> {
    return this.sessionRepository.manager.transaction(async (tx) => {
      const session = await tx.findOne(RunningSession, {
        where: { id: sessionId, user_id: userId },
        lock: { mode: 'pessimistic_write' },
      });
      this.assertActive(session);

      const user = await tx.findOne(User, { where: { id: userId } });
      const km = session.distance_meters / 1000.0;
      await tx.increment(User, { id: userId }, 'personal_km', km);
      if (user?.university_id) {
        await tx.increment(University, { id: user.university_id }, 'total_season_km', km);
      }
      await tx.update(RunningSession, session.id, { status: 'COMPLETED' });

      return {
        sessionId: session.id,
        distanceMeters: session.distance_meters,
        durationSeconds: session.duration_seconds,
        addedKm: Number(km.toFixed(2)),
      };
    });
  }

  private signingKeyOf(sessionId: string): string {
    return deriveSigningKey(this.config.getOrThrow<string>('JWT_SECRET'), sessionId);
  }

  /** Sai chữ ký hoặc gửi lại cửa sổ cũ: loại Phiên chạy và ghi nhật ký GIGO. */
  private async assertAuthentic(
    session: RunningSession,
    dto: TelemetryPayloadDto,
    proof?: WindowProof,
  ): Promise<void> {
    const signed =
      !!proof?.rawBody &&
      !!proof.signature &&
      isValidSignature(this.signingKeyOf(session.id), proof.rawBody, proof.signature);
    const fresh = dto.seq !== undefined && dto.seq > session.last_window_seq;

    if (!signed || !fresh) {
      await this.rejectSession(session.user_id, session, 'ERR_205', dto, null);
      throw new BadRequestException({
        code: 'ERR_205',
        message: 'INVALID_SIGNATURE: Cửa sổ cảm biến sai chữ ký hoặc đã được gửi trước đó.',
      });
    }
    session.last_window_seq = dto.seq;
  }

  /** Phiên chạy của chính Sinh viên này và còn ACTIVE. */
  private async loadActiveSession(userId: string, sessionId: string): Promise<RunningSession> {
    // Lọc theo cả user_id: phiên của người khác trả 404 như không tồn tại.
    const session = await this.sessionRepository.findOne({ where: { id: sessionId, user_id: userId } });
    this.assertActive(session);
    return session;
  }

  private assertActive(session: RunningSession | null): void {
    if (!session) {
      throw new NotFoundException({
        code: 'ERR_204',
        message: 'SESSION_NOT_FOUND: Không tìm thấy Phiên chạy.',
      });
    }
    if (session.status === 'REJECTED') {
      throw new BadRequestException({
        code: session.rejection_reason ?? 'ERR_202',
        message: 'SESSION_REJECTED: Phiên chạy đã bị loại, không nhận thêm dữ liệu.',
      });
    }
    if (session.status !== 'ACTIVE') {
      throw new NotFoundException({
        code: 'ERR_204',
        message: 'SESSION_NOT_FOUND: Phiên chạy đã kết thúc.',
      });
    }
  }

  /** Ghi nhật ký GIGO; nếu đã có Phiên chạy thì chuyển nó sang REJECTED. Cửa sổ đầu bị loại không tạo Phiên. */
  private async rejectSession(
    userId: string,
    session: RunningSession | null,
    errorCode: string,
    dto: TelemetryPayloadDto,
    biometric: BiometricCheckResult | null,
  ): Promise<void> {
    let sessionId: string | null = null;
    if (session) {
      session.status = 'REJECTED';
      session.is_valid = false;
      session.rejection_reason = errorCode;
      sessionId = (await this.sessionRepository.save(session)).id;
    }

    await this.auditRepository.save(
      this.auditRepository.create({
        user_id: userId,
        session_id: sessionId,
        rejection_type: errorCode,
        raw_gps_speed_mps: dto.averageSpeedMps,
        imu_cadence_spm: biometric?.analysis.cadenceSpm ?? 0,
        vertical_energy_g: biometric?.analysis.amplitudeG ?? null,
        gps_accuracy_m: dto.horizontalAccuracy,
        detected_at_h3: null,
      }),
    );
  }

  private toResult(session: RunningSession, biometric: BiometricCheckResult): VerifyWindowResultDto {
    const { analysis } = biometric;
    return {
      sessionId: session.id,
      windowPassed: biometric.isValid,
      consecutiveFailures: session.consecutive_biometric_failures,
      biometricApplied: biometric.applied,
      cadenceSpm: analysis.cadenceSpm,
      dominantFrequencyHz: analysis.dominantFrequencyHz,
      amplitudeG: analysis.amplitudeG,
      peakProminence: analysis.peakProminence,
      message: biometric.message,
    };
  }
}
