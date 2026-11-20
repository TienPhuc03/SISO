import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { AntiGigoService, BiometricCheckResult } from './anti-gigo.service';
import { TelemetryPayloadDto } from './dto/telemetry-payload.dto';
import { VerifyWindowResultDto } from './dto/verify-window-response.dto';
import { FinishSessionResultDto } from './dto/finish-session.dto';
import { SessionDetailDto, SessionSummaryDto } from './dto/session-history.dto';
import { buildRoute, filterPlausiblePoints } from './session-route';
import { RunningSession } from '../../entities/running-session.entity';
import { GigoAuditLog } from '../../entities/gigo-audit-log.entity';
import { GpsPoint, SessionWindow } from '../../entities/session-window.entity';
import { User } from '../../entities/user.entity';
import { University } from '../../entities/university.entity';
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

/** Điểm GPS được lệch tối đa bấy nhiêu ms ra ngoài khoảng mẫu IMU của cửa sổ (GPS và IMU không cùng nhịp). */
export const GPS_POINT_WINDOW_TOLERANCE_MS = 1000;

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
    // Cửa sổ đầu: chưa có Phiên chạy (chỉ tạo khi qua Cổng Động học), chưa ai biết sessionId nên không cần khoá.
    // Vẫn chạy trong transaction để Phiên chạy và cửa sổ 0 cùng được lưu hoặc cùng không.
    if (!dto.sessionId) {
      const outcome = await this.sessionRepository.manager.transaction((tx) =>
        this.processWindow(
          tx.getRepository(RunningSession),
          tx.getRepository(GigoAuditLog),
          tx.getRepository(SessionWindow),
          userId,
          null,
          dto,
        ),
      );
      if (outcome.rejection) throw outcome.rejection;
      return { ...outcome.result, signingKey: this.signingKeyOf(outcome.result.sessionId) };
    }

    // Các cửa sổ sau: khoá dòng Phiên chạy tới khi commit, để hai request đến cùng lúc (gửi lại
    // cùng seq, hay hai seq chồng nhau) xử lý lần lượt: không lọt cửa sổ gửi lại, không mất km.
    const outcome = await this.sessionRepository.manager.transaction(async (tx) => {
      const sessions = tx.getRepository(RunningSession);
      const session = await this.loadActiveSession(sessions, userId, dto.sessionId);
      return this.processWindow(
        sessions,
        tx.getRepository(GigoAuditLog),
        tx.getRepository(SessionWindow),
        userId,
        session,
        dto,
        proof,
      );
    });
    // Ném SAU khi commit: trạng thái REJECTED và nhật ký GIGO phải được lưu, không bị rollback.
    if (outcome.rejection) throw outcome.rejection;
    return outcome.result;
  }

  /**
   * Chạy hai Cổng trên một cửa sổ và lưu kết quả vào Phiên chạy ([existing] = null với cửa sổ đầu).
   * Bị loại thì trả lỗi (không ném) để lời gọi ném sau khi transaction đã commit.
   */
  private async processWindow(
    sessions: Repository<RunningSession>,
    audits: Repository<GigoAuditLog>,
    windows: Repository<SessionWindow>,
    userId: string,
    existing: RunningSession | null,
    dto: TelemetryPayloadDto,
    proof?: WindowProof,
  ): Promise<WindowOutcome> {
    const reject = async (
      session: RunningSession | null,
      code: string,
      message: string,
      biometric: BiometricCheckResult | null,
    ): Promise<WindowOutcome> => {
      await this.rejectSession(sessions, audits, userId, session, code, dto, biometric);
      return { rejection: new BadRequestException({ code, message }) };
    };

    // Cửa sổ đầu chưa có khoá nên chưa ký được; mọi cửa sổ sau bắt buộc ký.
    if (existing && !this.isAuthentic(existing, dto, proof)) {
      return reject(
        existing,
        'ERR_205',
        'INVALID_SIGNATURE: Cửa sổ cảm biến sai chữ ký hoặc đã được gửi trước đó.',
        null,
      );
    }
    if (existing) existing.last_window_seq = dto.seq;

    // Vệt GPS lệch thời gian là lỗi client, không phải gian lận: chỉ bỏ cửa sổ (như ERR_203), không loại Phiên.
    if (!this.gpsPointsInsideWindow(dto)) {
      return {
        rejection: new BadRequestException({
          code: 'ERR_206',
          message: 'INVALID_GPS_POINTS: Điểm GPS nằm ngoài thời gian của cửa sổ cảm biến.',
        }),
      };
    }

    // Tầng 1: Cổng Động học (DEV 1). Không cho bỏ qua lần nào.
    const kinematic = this.antiGigoService.validateKinematics(
      dto.averageSpeedMps,
      dto.horizontalAccuracy,
      dto.isMocked,
    );
    if (!kinematic.isValid) {
      // ERR_203 là mất tín hiệu tạm thời (SRS: tạm dừng đo): bỏ cửa sổ này, giữ Phiên chạy.
      if (kinematic.errorCode === 'ERR_203') {
        return { rejection: new BadRequestException({ code: kinematic.errorCode, message: kinematic.message }) };
      }
      return reject(existing, kinematic.errorCode, kinematic.message, null);
    }

    const session =
      existing ??
      sessions.create({
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
      return reject(session, 'ERR_202', biometric.message, biometric);
    }

    // Server tự cộng quãng đường và thời gian (hợp đồng #3: không tin km do client tự báo).
    const { windowSeconds } = biometric.analysis;
    session.distance_meters = session.distance_meters + dto.averageSpeedMps * windowSeconds;
    session.duration_seconds = Math.round(session.duration_seconds + windowSeconds);
    const saved = await sessions.save(session);

    // Lưu cửa sổ cho Lịch sử Phiên chạy (cùng transaction với tổng quãng đường). Cửa sổ đầu là seq 0.
    // Chỉ lưu điểm đi tới được từ điểm đã lưu trước đó: toạ độ bịa không kéo được Đường chạy (và Vòng khép) đi xa.
    const anchor = existing ? await this.lastStoredPoint(windows, saved.id) : null;
    await windows.insert({
      session_id: saved.id,
      seq: existing ? dto.seq : 0,
      speed_mps: dto.averageSpeedMps,
      cadence_spm: Math.round(biometric.analysis.cadenceSpm),
      passed: biometric.isValid,
      gps_points: filterPlausiblePoints(dto.gpsPoints ?? [], anchor),
      recorded_at: new Date(dto.imuSamples[0].timestamp),
    });

    return { result: this.toResult(saved, biometric) };
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
      await tx.update(RunningSession, session.id, { status: 'COMPLETED', finished_at: new Date() });

      return {
        sessionId: session.id,
        distanceMeters: session.distance_meters,
        durationSeconds: session.duration_seconds,
        addedKm: Number(km.toFixed(2)),
      };
    });
  }

  /**
   * Điểm GPS cuối đã lưu của Phiên chạy, bỏ qua Cửa sổ không có điểm: nếu chỉ lấy Cửa sổ ngay trước,
   * gửi một Cửa sổ rỗng là xoá được điểm neo rồi dịch chuyển tức thời.
   */
  private async lastStoredPoint(windows: Repository<SessionWindow>, sessionId: string): Promise<GpsPoint | null> {
    const rows: { point: GpsPoint }[] = await windows.query(
      `SELECT gps_points -> -1 AS point FROM public.session_windows
       WHERE session_id = $1 AND jsonb_array_length(gps_points) > 0
       ORDER BY seq DESC LIMIT 1`,
      [sessionId],
    );
    return rows[0]?.point ?? null;
  }

  /** Mọi điểm GPS nằm trong khoảng mẫu IMU của cửa sổ, nới thêm GPS_POINT_WINDOW_TOLERANCE_MS mỗi đầu. */
  private gpsPointsInsideWindow(dto: TelemetryPayloadDto): boolean {
    const from = dto.imuSamples[0].timestamp - GPS_POINT_WINDOW_TOLERANCE_MS;
    const to = dto.imuSamples[dto.imuSamples.length - 1].timestamp + GPS_POINT_WINDOW_TOLERANCE_MS;
    return (dto.gpsPoints ?? []).every((p) => p.timestamp >= from && p.timestamp <= to);
  }

  /** Lịch sử Phiên chạy của chính Sinh viên, mới nhất trước. */
  async listSessions(userId: string, page: number, limit: number): Promise<SessionSummaryDto[]> {
    const rows = await this.sessionRepository.find({
      where: { user_id: userId },
      order: { created_at: 'DESC' },
      skip: (page - 1) * limit,
      take: limit,
    });
    return rows.map((s) => this.toSummary(s));
  }

  /** Chi tiết một Phiên chạy: tổng, chuỗi cửa sổ, Đường chạy. Phiên của người khác trả 404 như không tồn tại. */
  async getSession(userId: string, sessionId: string): Promise<SessionDetailDto> {
    const session = await this.sessionRepository.findOne({ where: { id: sessionId, user_id: userId } });
    if (!session) {
      throw new NotFoundException({ code: 'ERR_204', message: 'SESSION_NOT_FOUND: Không tìm thấy Phiên chạy.' });
    }
    const windows = await this.sessionRepository.manager.find(SessionWindow, {
      where: { session_id: session.id },
      order: { seq: 'ASC' },
    });
    return {
      ...this.toSummary(session),
      windows: windows.map((w) => ({
        seq: w.seq,
        speedMps: w.speed_mps,
        cadenceSpm: w.cadence_spm,
        passed: w.passed,
        recordedAt: w.recorded_at,
      })),
      route: buildRoute(windows),
    };
  }

  private toSummary(s: RunningSession): SessionSummaryDto {
    return {
      sessionId: s.id,
      status: s.status,
      sessionType: s.session_type,
      distanceMeters: s.distance_meters,
      durationSeconds: s.duration_seconds,
      hexCount: s.hex_count,
      rejectionReason: s.rejection_reason ?? null,
      startedAt: s.created_at,
      finishedAt: s.finished_at ?? null,
    };
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
    sessions: Repository<RunningSession>,
    audits: Repository<GigoAuditLog>,
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
      session.finished_at = new Date();
      sessionId = (await sessions.save(session)).id;
    }

    await audits.save(
      audits.create({
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
