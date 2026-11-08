import { STANDARD_GRAVITY } from './gait-analyzer';
import { ImuSampleDto, IMU_WINDOW_SIZE } from './dto/telemetry-payload.dto';

/**
 * Mẫu gia tốc TỔNG HỢP (không phải dữ liệu thật) cho test Cổng Sinh trắc.
 * Đơn vị m/s² như điện thoại gửi. Thay bằng mẫu thật khi có ticket #9.
 */
export interface SyntheticOptions {
  /** Tần số bước (Hz); 0 = không có nhịp bước. */
  stepHz?: number;
  /** Biên độ dao động theo bước, đơn vị G. */
  stepAmplitudeG?: number;
  /** Rung động cơ (Hz) và biên độ (G), mô phỏng xe máy. */
  vibrationHz?: number;
  vibrationAmplitudeG?: number;
  /** Nhiễu ngẫu nhiên (G). */
  noiseG?: number;
  sampleRateHz?: number;
  count?: number;
  seed?: number;
}

export function syntheticWindow(opts: SyntheticOptions = {}): ImuSampleDto[] {
  const {
    stepHz = 0,
    stepAmplitudeG = 0,
    vibrationHz = 0,
    vibrationAmplitudeG = 0,
    noiseG = 0.02,
    sampleRateHz = 50,
    count = IMU_WINDOW_SIZE,
    seed = 42,
  } = opts;
  let state = seed;
  const noise = () => {
    state = (state * 1103515245 + 12345) % 2147483648;
    return state / 2147483648 - 0.5;
  };
  const start = 1_762_300_000_000;
  return Array.from({ length: count }, (_, i) => {
    const t = i / sampleRateHz;
    const verticalG =
      1 +
      stepAmplitudeG * Math.sin(2 * Math.PI * stepHz * t) +
      vibrationAmplitudeG * Math.sin(2 * Math.PI * vibrationHz * t) +
      noiseG * noise();
    return {
      ax: STANDARD_GRAVITY * noiseG * noise(),
      ay: STANDARD_GRAVITY * noiseG * noise(),
      az: STANDARD_GRAVITY * verticalG,
      timestamp: start + Math.round((i * 1000) / sampleRateHz),
    };
  });
}

/** Các tình huống chuẩn dùng chung giữa các file test. */
export const SCENARIOS = {
  /** Chạy bộ ~162 SPM, dao động mạnh. */
  running: () => syntheticWindow({ stepHz: 2.7, stepAmplitudeG: 0.8, noiseG: 0.1 }),
  /** Đi bộ nhanh ~114 SPM. */
  walking: () => syntheticWindow({ stepHz: 1.9, stepAmplitudeG: 0.4, noiseG: 0.05 }),
  /** Xe máy rà chậm: chỉ rung động cơ 10 Hz rất nhỏ, không có nhịp bước. */
  motorbike: () => syntheticWindow({ vibrationHz: 10, vibrationAmplitudeG: 0.05, noiseG: 0.03 }),
  /** Đứng yên. */
  still: () => syntheticWindow({ noiseG: 0.005 }),
};
