import { fft } from 'fft-js';

/**
 * Phân tích Nhịp bước từ một cửa sổ gia tốc (Cổng Sinh trắc, Module 4).
 *
 * Hàm thuần, không phụ thuộc NestJS, để test trực tiếp bằng mẫu tổng hợp và
 * để có thể đổi thư viện FFT mà không động tới AntiGigoService.
 * Cơ sở: docs/research/fft-cadence.md (ticket wayfinder #7).
 */

/** Gia tốc trọng trường chuẩn, dùng để quy đổi m/s² sang G. */
export const STANDARD_GRAVITY = 9.80665;

/** Dải tần sinh học của bước chạy/đi: 1,5–4 Hz (90–240 SPM). */
export const GAIT_BAND_HZ = { min: 1.5, max: 4.0 } as const;

/** Tần số lấy mẫu dự kiến; chỉ dùng khi timestamp không hợp lệ. */
export const NOMINAL_SAMPLE_RATE_HZ = 50;

export interface AccelSample {
  /** Gia tốc trục x, đơn vị m/s² (có cả trọng lực), như sensors_plus trả về. */
  ax: number;
  ay: number;
  az: number;
  /** Thời điểm lấy mẫu, mili giây. */
  timestamp: number;
}

export interface GaitAnalysis {
  /** Tần số lấy mẫu thật, tính từ timestamp. */
  sampleRateHz: number;
  /** Thời lượng cửa sổ (giây), tính từ timestamp. */
  windowSeconds: number;
  /** Tần số đỉnh trong dải sinh học (Hz); 0 nếu không có tín hiệu. */
  dominantFrequencyHz: number;
  /** Nhịp bước (bước/phút) = tần số đỉnh × 60. */
  cadenceSpm: number;
  /**
   * Biên độ dáng chạy (G): RMS của độ lớn gia tốc sau khi trừ trung bình, chỉ tính phần năng lượng
   * nằm trong dải 1,5–4 Hz (rung động cơ ngoài dải không được cộng vào).
   */
  amplitudeG: number;
  /** Độ rõ đỉnh: năng lượng quanh đỉnh / năng lượng cả dải sinh học (0..1). */
  peakProminence: number;
}

export function analyzeGait(samples: AccelSample[]): GaitAnalysis {
  const n = samples.length;
  const { sampleRateHz, windowSeconds } = measureSampleRate(samples);
  const empty: GaitAnalysis = {
    sampleRateHz,
    windowSeconds,
    dominantFrequencyHz: 0,
    cadenceSpm: 0,
    amplitudeG: 0,
    peakProminence: 0,
  };
  if (n < 4) return empty;

  // 1. Độ lớn gia tốc (G), không phụ thuộc hướng cầm điện thoại.
  const magnitude = samples.map((s) => Math.hypot(s.ax, s.ay, s.az) / STANDARD_GRAVITY);

  // 2. Trừ trung bình để bỏ thành phần trọng lực (DC); rmsG = RMS toàn phần của phần còn lại.
  const mean = magnitude.reduce((a, b) => a + b, 0) / n;
  const centered = magnitude.map((m) => m - mean);
  const rmsG = Math.sqrt(centered.reduce((acc, x) => acc + x * x, 0) / n);
  if (rmsG === 0) return empty;

  // 3. Cửa sổ Hann giảm rò phổ, rồi zero-pad lên luỹ thừa của 2 (fft-js bắt buộc).
  const size = nextPowerOfTwo(n);
  const signal = new Array<number>(size).fill(0);
  for (let i = 0; i < n; i++) {
    const hann = 0.5 * (1 - Math.cos((2 * Math.PI * i) / (n - 1)));
    signal[i] = centered[i] * hann;
  }

  const spectrum = fft(signal);
  const power = spectrum.slice(0, size / 2 + 1).map(([re, im]) => re * re + im * im);

  // 4. Tìm đỉnh trong dải sinh học. Tự tính f = k·fs/N (không dùng fftutil.fftFreq, xem ghi chú nghiên cứu).
  const binHz = sampleRateHz / size;
  const kMin = Math.max(1, Math.ceil(GAIT_BAND_HZ.min / binHz));
  const kMax = Math.min(power.length - 2, Math.floor(GAIT_BAND_HZ.max / binHz));
  if (kMax < kMin) return empty;

  let kPeak = kMin;
  let bandPower = 0;
  for (let k = kMin; k <= kMax; k++) {
    bandPower += power[k];
    if (power[k] > power[kPeak]) kPeak = k;
  }
  if (bandPower === 0) return empty;

  // 5. Nội suy parabol quanh đỉnh (trên biên độ) để vượt độ phân giải ~0,2 Hz của cửa sổ 5 s.
  const left = Math.sqrt(power[kPeak - 1]);
  const mid = Math.sqrt(power[kPeak]);
  const right = Math.sqrt(power[kPeak + 1]);
  const denom = left - 2 * mid + right;
  const delta = denom === 0 ? 0 : clamp((0.5 * (left - right)) / denom, -0.5, 0.5);
  const dominantFrequencyHz = (kPeak + delta) * binHz;

  // 6. Độ rõ đỉnh: búp chính của cửa sổ Hann trải trên ~3 bin quanh đỉnh.
  const peakPower = power[kPeak - 1] + power[kPeak] + power[kPeak + 1];
  const peakProminence = clamp(peakPower / bandPower, 0, 1);

  // 7. Biên độ CHỈ tính phần năng lượng trong dải bước chân. Nếu dùng RMS toàn phần, rung động cơ
  //    mạnh ngoài dải (vd. 10 Hz, 0,5G) sẽ vượt ngưỡng biên độ và xe máy lọt qua Cổng Sinh trắc.
  let totalPower = 0;
  for (let k = 1; k < power.length; k++) totalPower += power[k];
  const bandShare = totalPower === 0 ? 0 : bandPower / totalPower;
  const gaitAmplitudeG = rmsG * Math.sqrt(bandShare);

  return {
    sampleRateHz,
    windowSeconds,
    dominantFrequencyHz: round(dominantFrequencyHz, 2),
    cadenceSpm: Math.round(dominantFrequencyHz * 60),
    amplitudeG: round(gaitAmplitudeG, 3),
    peakProminence: round(peakProminence, 3),
  };
}

/** Tần số lấy mẫu và thời lượng từ timestamp; quay về 50 Hz nếu timestamp không dùng được. */
export function measureSampleRate(samples: AccelSample[]): {
  sampleRateHz: number;
  windowSeconds: number;
} {
  const n = samples.length;
  if (n >= 2) {
    const spanMs = samples[n - 1].timestamp - samples[0].timestamp;
    if (Number.isFinite(spanMs) && spanMs > 0) {
      const sampleRateHz = ((n - 1) * 1000) / spanMs;
      // Bỏ qua timestamp vô lý (ví dụ cùng một giá trị lặp lại) thay vì tin vào nó.
      if (sampleRateHz >= 10 && sampleRateHz <= 500) {
        return { sampleRateHz, windowSeconds: n / sampleRateHz };
      }
    }
  }
  return { sampleRateHz: NOMINAL_SAMPLE_RATE_HZ, windowSeconds: n / NOMINAL_SAMPLE_RATE_HZ };
}

function nextPowerOfTwo(n: number): number {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

function clamp(x: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, x));
}

function round(x: number, digits: number): number {
  const f = 10 ** digits;
  return Math.round(x * f) / f;
}
