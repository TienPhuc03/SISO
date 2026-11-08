import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AntiGigoService, BiometricCheckResult } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResultDto } from './dto/verify-window-response.dto';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';

/** Số cửa sổ liên tiếp không qua Cổng Sinh trắc thì Phiên chạy bị loại. */
export const MAX_CONSECUTIVE_BIOMETRIC_FAILURES = 2;

/**
 * Kiểm định Phiên chạy theo từng cửa sổ 256 mẫu (Module 4).
 *
 * - Cửa sổ đầu tiên (không có sessionId) tạo Phiên chạy ACTIVE và trả sessionId.
 * - Cổng Động học không qua: loại ngay.
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
  ) {}

  async verifyWindow(userId: string, dto: TelemetryPayloadDto): Promise<VerifyWindowResultDto> {
    const session = await this.loadOrStartSession(userId, dto.sessionId);

    // Tầng 1: Cổng Động học (DEV 1). Không cho bỏ qua lần nào.
    const kinematic = this.antiGigoService.validateKinematics(
      dto.averageSpeedMps,
      dto.horizontalAccuracy,
      dto.isMocked,
    );
    if (!kinematic.isValid) {
      await this.rejectSession(session, kinematic.errorCode, dto, null);
      throw new BadRequestException({ code: kinematic.errorCode, message: kinematic.message });
    }

    // Tầng 2: Cổng Sinh trắc. Một cửa sổ lẻ không qua chỉ là cảnh báo.
    const biometric = this.antiGigoService.validateBiometrics(dto.averageSpeedMps, dto.imuSamples);
    session.consecutive_biometric_failures = biometric.isValid
      ? 0
      : session.consecutive_biometric_failures + 1;

    if (session.consecutive_biometric_failures >= MAX_CONSECUTIVE_BIOMETRIC_FAILURES) {
      await this.rejectSession(session, 'ERR_202', dto, biometric);
      throw new BadRequestException({ code: 'ERR_202', message: biometric.message });
    }

    // Server tự cộng quãng đường và thời gian (hợp đồng #3: không tin km do client tự báo).
    const { windowSeconds } = biometric.analysis;
    session.distance_meters = session.distance_meters + dto.averageSpeedMps * windowSeconds;
    session.duration_seconds = Math.round(session.duration_seconds + windowSeconds);
    await this.sessionRepository.save(session);

    return this.toResult(session, biometric);
  }

  /** Phiên chạy của chính Sinh viên này và còn ACTIVE; không có sessionId thì tạo mới. */
  private async loadOrStartSession(userId: string, sessionId?: string): Promise<RunningSession> {
    if (!sessionId) {
      return this.sessionRepository.save(
        this.sessionRepository.create({
          user_id: userId,
          session_type: 'FREE_RUN',
          status: 'ACTIVE',
          distance_meters: 0,
          duration_seconds: 0,
          consecutive_biometric_failures: 0,
          is_valid: true,
        }),
      );
    }

    // Lọc theo cả user_id: phiên của người khác trả 404 như không tồn tại.
    const session = await this.sessionRepository.findOne({ where: { id: sessionId, user_id: userId } });
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
    return session;
  }

  private async rejectSession(
    session: RunningSession,
    errorCode: string,
    dto: TelemetryPayloadDto,
    biometric: BiometricCheckResult | null,
  ): Promise<void> {
    session.status = 'REJECTED';
    session.is_valid = false;
    session.rejection_reason = errorCode;
    await this.sessionRepository.save(session);

    await this.auditRepository.save(
      this.auditRepository.create({
        user_id: session.user_id,
        session_id: session.id,
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
