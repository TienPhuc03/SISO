import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AntiGigoService, BiometricCheckResult } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResultDto } from './dto/verify-window-response.dto';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';
import { deriveSigningKey, isValidSignature } from './telemetry-signature';

/** Bằng chứng toàn vẹn của một request: nguyên văn body và chữ ký trong header. */
export interface WindowProof {
  rawBody?: Buffer;
  signature?: string;
}

/** Kết quả xử lý một cửa sổ: hoặc kết quả trả client, hoặc lỗi loại Phiên chạy (ném sau khi commit). */
type WindowOutcome =
  | { result: VerifyWindowResultDto; rejection?: undefined }
  | { rejection: BadRequestException; result?: undefined };

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
    private readonly config: ConfigService,
  ) {}

  async verifyWindow(
    userId: string,
    dto: TelemetryPayloadDto,
    proof?: WindowProof,
  ): Promise<VerifyWindowResultDto> {
    // Cửa sổ đầu: dòng Phiên chạy vừa tạo, chưa ai khác biết sessionId nên không cần khoá.
    if (!dto.sessionId) {
      const session = await this.startSession(userId);
      const outcome = await this.processWindow(this.sessionRepository, this.auditRepository, session, dto);
      if (outcome.rejection) throw outcome.rejection;
      return { ...outcome.result, signingKey: this.signingKeyOf(session.id) };
    }

    // Các cửa sổ sau: khoá dòng Phiên chạy tới khi commit, để hai request đến cùng lúc (gửi lại
    // cùng seq, hay hai seq chồng nhau) xử lý lần lượt: không lọt cửa sổ gửi lại, không mất km.
    const outcome = await this.sessionRepository.manager.transaction(async (tx) => {
      const sessions = tx.getRepository(RunningSession);
      const session = await this.loadActiveSession(sessions, userId, dto.sessionId);
      return this.processWindow(sessions, tx.getRepository(GigoAuditLog), session, dto, proof);
    });
    // Ném SAU khi commit: trạng thái REJECTED và nhật ký GIGO phải được lưu, không bị rollback.
    if (outcome.rejection) throw outcome.rejection;
    return outcome.result;
  }

  /**
   * Chạy hai Cổng trên một cửa sổ và lưu kết quả vào Phiên chạy. Bị loại thì trả lỗi (không ném)
   * để lời gọi ném sau khi transaction đã commit.
   */
  private async processWindow(
    sessions: Repository<RunningSession>,
    audits: Repository<GigoAuditLog>,
    session: RunningSession,
    dto: TelemetryPayloadDto,
    proof?: WindowProof,
  ): Promise<WindowOutcome> {
    const reject = async (
      code: string,
      message: string,
      biometric: BiometricCheckResult | null,
    ): Promise<WindowOutcome> => {
      await this.rejectSession(sessions, audits, session, code, dto, biometric);
      return { rejection: new BadRequestException({ code, message }) };
    };

    // Cửa sổ đầu chưa có khoá nên chưa ký được; mọi cửa sổ sau bắt buộc ký.
    if (dto.sessionId && !this.isAuthentic(session, dto, proof)) {
      return reject(
        'ERR_205',
        'INVALID_SIGNATURE: Cửa sổ cảm biến sai chữ ký hoặc đã được gửi trước đó.',
        null,
      );
    }
    if (dto.sessionId) session.last_window_seq = dto.seq;

    // Tầng 1: Cổng Động học (DEV 1). Không cho bỏ qua lần nào.
    const kinematic = this.antiGigoService.validateKinematics(
      dto.averageSpeedMps,
      dto.horizontalAccuracy,
      dto.isMocked,
    );
    if (!kinematic.isValid) return reject(kinematic.errorCode, kinematic.message, null);

    // Tầng 2: Cổng Sinh trắc. Một cửa sổ lẻ không qua chỉ là cảnh báo.
    const biometric = this.antiGigoService.validateBiometrics(dto.averageSpeedMps, dto.imuSamples);
    session.consecutive_biometric_failures = biometric.isValid
      ? 0
      : session.consecutive_biometric_failures + 1;

    if (session.consecutive_biometric_failures >= MAX_CONSECUTIVE_BIOMETRIC_FAILURES) {
      return reject('ERR_202', biometric.message, biometric);
    }

    // Server tự cộng quãng đường và thời gian (hợp đồng #3: không tin km do client tự báo).
    const { windowSeconds } = biometric.analysis;
    session.distance_meters = session.distance_meters + dto.averageSpeedMps * windowSeconds;
    session.duration_seconds = Math.round(session.duration_seconds + windowSeconds);
    await sessions.save(session);

    return { result: this.toResult(session, biometric) };
  }

  private signingKeyOf(sessionId: string): string {
    return deriveSigningKey(this.config.getOrThrow<string>('JWT_SECRET'), sessionId);
  }

  /** Đúng chữ ký của Phiên chạy và seq mới hơn mọi cửa sổ đã nhận (không phải gửi lại). */
  private isAuthentic(session: RunningSession, dto: TelemetryPayloadDto, proof?: WindowProof): boolean {
    const signed =
      !!proof?.rawBody &&
      !!proof.signature &&
      isValidSignature(this.signingKeyOf(session.id), proof.rawBody, proof.signature);
    const fresh = dto.seq !== undefined && dto.seq > session.last_window_seq;
    return signed && fresh;
  }

  private startSession(userId: string): Promise<RunningSession> {
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

  /** Phiên chạy của chính Sinh viên này và còn ACTIVE, khoá dòng tới hết transaction. */
  private async loadActiveSession(
    sessions: Repository<RunningSession>,
    userId: string,
    sessionId: string,
  ): Promise<RunningSession> {
    // Lọc theo cả user_id: phiên của người khác trả 404 như không tồn tại.
    const session = await sessions.findOne({
      where: { id: sessionId, user_id: userId },
      lock: { mode: 'pessimistic_write' },
    });
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
    sessions: Repository<RunningSession>,
    audits: Repository<GigoAuditLog>,
    session: RunningSession,
    errorCode: string,
    dto: TelemetryPayloadDto,
    biometric: BiometricCheckResult | null,
  ): Promise<void> {
    session.status = 'REJECTED';
    session.is_valid = false;
    session.rejection_reason = errorCode;
    await sessions.save(session);

    await audits.save(
      audits.create({
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
