import { AntiGigoService, BIOMETRIC_THRESHOLDS, BiometricCheckResult, GigoCheckResult } from './anti-gigo.service';
import { buildImuWindows, accelRateHz, ImuLog, ImuLogLabel } from './imu-log';

/**
 * Hiệu chỉnh Cổng Sinh trắc bằng mẫu IMU thật (ticket #9): chạy ĐÚNG logic server
 * (`validateKinematics`, `validateBiometrics`, luật 2 cửa sổ liên tiếp) trên từng log.
 */

/** Giống `MAX_CONSECUTIVE_BIOMETRIC_FAILURES` trong telemetry.service.ts (giữ đồng bộ). */
export const SESSION_REJECT_AFTER_FAILURES = 2;

export interface WindowEvaluation {
  index: number;
  endSeconds: number;
  speedMps: number;
  accuracyM: number;
  kinematic: GigoCheckResult;
  biometric: BiometricCheckResult;
}

export interface SessionOutcome {
  rejected: boolean;
  /** ERR_201/202/203 nếu bị loại. */
  code: string | null;
  /** Cửa sổ (từ 0) làm Phiên chạy bị loại. */
  atWindow: number | null;
  /** Thời điểm bị loại, tính từ đầu log (giây). */
  atSeconds: number | null;
  /** Bị loại vì Cổng Động học (GPS), không liên quan ngưỡng sinh trắc. */
  byKinematic: boolean;
}

export interface LogEvaluation {
  name: string;
  label: ImuLogLabel;
  note: string;
  durationSeconds: number;
  accelRateHz: number;
  windows: WindowEvaluation[];
  session: SessionOutcome;
}

export function evaluateLog(name: string, log: ImuLog, service = new AntiGigoService()): LogEvaluation {
  const windows = buildImuWindows(log).map((w) => ({
    index: w.index,
    endSeconds: w.endT / 1000,
    speedMps: w.averageSpeedMps,
    accuracyM: w.horizontalAccuracy,
    kinematic: service.validateKinematics(w.averageSpeedMps, w.horizontalAccuracy, w.isMocked),
    biometric: service.validateBiometrics(w.averageSpeedMps, w.samples),
  }));

  let session: SessionOutcome = { rejected: false, code: null, atWindow: null, atSeconds: null, byKinematic: false };
  let consecutive = 0;
  for (const w of windows) {
    if (!w.kinematic.isValid) {
      session = { rejected: true, code: w.kinematic.errorCode, atWindow: w.index, atSeconds: w.endSeconds, byKinematic: true };
      break;
    }
    consecutive = w.biometric.isValid ? 0 : consecutive + 1;
    if (consecutive >= SESSION_REJECT_AFTER_FAILURES) {
      session = { rejected: true, code: 'ERR_202', atWindow: w.index, atSeconds: w.endSeconds, byKinematic: false };
      break;
    }
  }

  const durationMs = Math.max(log.accel.at(-1)?.t ?? 0, log.gps.at(-1)?.t ?? 0);
  return {
    name,
    label: log.header.label,
    note: log.header.note,
    durationSeconds: durationMs / 1000,
    accelRateHz: accelRateHz(log),
    windows,
    session,
  };
}

export interface Percentiles {
  p5: number;
  median: number;
  p95: number;
}

export interface LabelSummary {
  label: ImuLogLabel;
  logs: number;
  windows: number;
  /** Cửa sổ đủ tốc độ để Cổng Sinh trắc xét (>= minSpeedMps). */
  appliedWindows: number;
  /** Trong số cửa sổ được xét: tỉ lệ qua cổng (0..1). */
  biometricPassRate: number;
  /** Trong số cửa sổ được xét: tỉ lệ ERR_202. */
  biometricFailRate: number;
  /** Số cửa sổ trượt Cổng Động học (GPS mock, sai số > 20 m, > 9 m/s). */
  kinematicFailures: number;
  sessionsRejected: number;
  /** Thời điểm sớm nhất/muộn nhất bị loại vì sinh trắc (giây). */
  rejectSeconds: { min: number; max: number } | null;
  /** Phân phối trên các cửa sổ được xét. */
  cadenceSpm: Percentiles | null;
  amplitudeG: Percentiles | null;
  peakProminence: Percentiles | null;
}

export function summarizeByLabel(evaluations: LogEvaluation[]): LabelSummary[] {
  const labels = [...new Set(evaluations.map((e) => e.label))];
  return labels.map((label) => {
    const evs = evaluations.filter((e) => e.label === label);
    const all = evs.flatMap((e) => e.windows);
    const applied = all.filter((w) => w.biometric.applied);
    const passed = applied.filter((w) => w.biometric.isValid).length;
    const bioRejects = evs.filter((e) => e.session.rejected && !e.session.byKinematic);
    return {
      label,
      logs: evs.length,
      windows: all.length,
      appliedWindows: applied.length,
      biometricPassRate: applied.length ? passed / applied.length : 0,
      biometricFailRate: applied.length ? (applied.length - passed) / applied.length : 0,
      kinematicFailures: all.filter((w) => !w.kinematic.isValid).length,
      sessionsRejected: evs.filter((e) => e.session.rejected).length,
      rejectSeconds: bioRejects.length
        ? {
            min: Math.min(...bioRejects.map((e) => e.session.atSeconds)),
            max: Math.max(...bioRejects.map((e) => e.session.atSeconds)),
          }
        : null,
      cadenceSpm: percentiles(applied.map((w) => w.biometric.analysis.cadenceSpm)),
      amplitudeG: percentiles(applied.map((w) => w.biometric.analysis.amplitudeG)),
      peakProminence: percentiles(applied.map((w) => w.biometric.analysis.peakProminence)),
    };
  });
}

export type MetricKey = 'cadenceSpm' | 'amplitudeG' | 'peakProminence';

export interface ThresholdAdvice {
  metric: MetricKey;
  current: number;
  /** p5 của chạy bộ (người thật phải ở trên ngưỡng). */
  runP5: number | null;
  /** p95 của xe máy (xe máy phải ở dưới ngưỡng). */
  motorbikeP95: number | null;
  /** true nếu runP5 > motorbikeP95: chỉ số này tách được hai nhóm. */
  separable: boolean | null;
  /** Điểm giữa khi tách được; null khi thiếu dữ liệu hoặc chồng lấn. */
  suggested: number | null;
  verdict: string;
}

const CURRENT: Record<MetricKey, number> = {
  cadenceSpm: BIOMETRIC_THRESHOLDS.minCadenceSpm,
  amplitudeG: BIOMETRIC_THRESHOLDS.minAmplitudeG,
  peakProminence: BIOMETRIC_THRESHOLDS.minPeakProminence,
};

/**
 * Gợi ý ngưỡng cho từng chỉ số: so p5 của chạy bộ với p95 của xe máy. Chỉ là gợi ý để người
 * quyết định; không tự đổi `BIOMETRIC_THRESHOLDS`.
 */
export function adviseThresholds(summaries: LabelSummary[]): ThresholdAdvice[] {
  const run = summaries.find((s) => s.label === 'run');
  const moto = summaries.find((s) => s.label === 'motorbike');
  return (Object.keys(CURRENT) as MetricKey[]).map((metric) => {
    const current = CURRENT[metric];
    const runP5 = run?.[metric]?.p5 ?? null;
    const motoP95 = moto?.[metric]?.p95 ?? null;
    if (runP5 === null || motoP95 === null) {
      return {
        metric,
        current,
        runP5,
        motorbikeP95: motoP95,
        separable: null,
        suggested: null,
        verdict: 'Thiếu dữ liệu chạy bộ hoặc xe máy (cần cửa sổ >= 2,5 m/s của cả hai).',
      };
    }
    const separable = runP5 > motoP95;
    const suggested = separable ? roundFor(metric, (runP5 + motoP95) / 2) : null;
    const currentOk = current < runP5 && current > motoP95;
    const verdict = !separable
      ? 'Chồng lấn: chỉ số này một mình không tách được chạy bộ và xe máy.'
      : currentOk
        ? 'Ngưỡng hiện tại nằm giữa hai nhóm: giữ nguyên được.'
        : current >= runP5
          ? 'Ngưỡng hiện tại quá cao: sẽ loại nhầm người chạy thật.'
          : 'Ngưỡng hiện tại thấp hơn xe máy: một mình chỉ số này không chặn được xe máy (xem các chỉ số khác).';
    return { metric, current, runP5, motorbikeP95: motoP95, separable, suggested, verdict };
  });
}

export function percentiles(values: number[]): Percentiles | null {
  if (values.length === 0) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const at = (p: number) => {
    const idx = (sorted.length - 1) * p;
    const lo = Math.floor(idx);
    const hi = Math.ceil(idx);
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (idx - lo);
  };
  return { p5: round3(at(0.05)), median: round3(at(0.5)), p95: round3(at(0.95)) };
}

function roundFor(metric: MetricKey, v: number): number {
  return metric === 'cadenceSpm' ? Math.round(v) : Math.round(v * 100) / 100;
}

function round3(v: number): number {
  return Math.round(v * 1000) / 1000;
}
