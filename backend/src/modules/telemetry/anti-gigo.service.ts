import { Injectable } from '@nestjs/common';
import { ImuSampleDto } from './dto/telemetry-payload.dto';
import { analyzeGait, GaitAnalysis } from './gait-analyzer';

export interface GigoCheckResult {
  isValid: boolean;
  errorCode: string | null;
  message: string;
}

@Injectable()
export class AntiGigoService {
  private readonly MAX_HUMAN_SPEED_MPS = 9.0; // 32.4 km/h

  /**
   * Tầng 1: Kinematic Gate - Kiểm tra vận tốc & gia tốc vật lý
   */
  validateKinematics(speedMps: number, accuracy: number, isMocked: boolean): GigoCheckResult {
    if (isMocked) {
      return {
        isValid: false,
        errorCode: 'ERR_201',
        message: 'MOCK_GPS_DETECTED: Phát hiện phần mềm giả lập tọa độ GPS.',
      };
    }

    if (accuracy > 20.0) {
      return {
        isValid: false,
        errorCode: 'ERR_203',
        message: 'GPS_ACCURACY_LOW: Độ sai số vệ tinh quá lớn (> 20m).',
      };
    }

    if (speedMps > this.MAX_HUMAN_SPEED_MPS) {
      return {
        isValid: false,
        errorCode: 'ERR_202',
        message: `VEHICLE_SPEED_MISMATCH: Vận tốc ${speedMps.toFixed(1)} m/s vượt ngưỡng sinh học người chạy bộ (< 9.0 m/s).`,
      };
    }

    return { isValid: true, errorCode: null, message: 'Kinematic hợp lệ' };
  }

  /**
   * Tầng 2: Cổng Sinh trắc. Phân tích phổ (FFT) một cửa sổ 256 mẫu gia tốc (m/s²) để lấy Nhịp bước,
   * rồi so với tốc độ: tốc độ chạy bộ mà không có dáng chạy thật thì nghi đi xe máy (ERR_202).
   * Chỉ đánh giá MỘT cửa sổ; luật "2 cửa sổ liên tiếp" nằm ở TelemetryService.
   */
  validateBiometrics(speedMps: number, imuSamples: ImuSampleDto[]): BiometricCheckResult {
    const analysis = analyzeGait(imuSamples ?? []);

    // Dưới ngưỡng tốc độ (đi bộ, chạy rất chậm) không xét: xe máy chạy chậm vậy không đáng kể.
    if (speedMps < BIOMETRIC_THRESHOLDS.minSpeedMps) {
      return {
        isValid: true,
        errorCode: null,
        message: 'Tốc độ thấp, chưa áp dụng Cổng Sinh trắc.',
        applied: false,
        analysis,
      };
    }

    const reasons: string[] = [];
    if (analysis.cadenceSpm < BIOMETRIC_THRESHOLDS.minCadenceSpm) {
      reasons.push(`Nhịp bước ${analysis.cadenceSpm} SPM < ${BIOMETRIC_THRESHOLDS.minCadenceSpm}`);
    }
    if (analysis.amplitudeG < BIOMETRIC_THRESHOLDS.minAmplitudeG) {
      reasons.push(`biên độ ${analysis.amplitudeG}G < ${BIOMETRIC_THRESHOLDS.minAmplitudeG}G`);
    }
    if (analysis.peakProminence < BIOMETRIC_THRESHOLDS.minPeakProminence) {
      reasons.push(`không có nhịp bước rõ (độ rõ đỉnh ${analysis.peakProminence})`);
    }

    if (reasons.length > 0) {
      return {
        isValid: false,
        errorCode: 'ERR_202',
        message: `VEHICLE_SPEED_MISMATCH: Tốc độ ${(speedMps * 3.6).toFixed(1)} km/h nhưng ${reasons.join(', ')} (nghi đi xe máy).`,
        applied: true,
        analysis,
      };
    }

    return {
      isValid: true,
      errorCode: null,
      message: 'Nhịp bước sinh học hợp lệ.',
      applied: true,
      analysis,
    };
  }
}

/**
 * Ngưỡng TẠM của Cổng Sinh trắc (SRS FR-03, ticket #7). Sẽ hiệu chỉnh bằng mẫu IMU thật
 * (ticket #9) và buổi test thực địa; giữ ở một chỗ để chỉnh không phải tìm khắp code.
 */
export const BIOMETRIC_THRESHOLDS = {
  /** Chỉ xét Cổng Sinh trắc khi tốc độ từ mức này trở lên (9 km/h). */
  minSpeedMps: 2.5,
  minCadenceSpm: 120,
  /** RMS độ lớn gia tốc sau khi trừ trung bình. */
  minAmplitudeG: 0.2,
  /** Tỉ lệ năng lượng quanh đỉnh trên năng lượng dải 1,5–4 Hz. */
  minPeakProminence: 0.3,
} as const;

export interface BiometricCheckResult {
  isValid: boolean;
  errorCode: 'ERR_202' | null;
  message: string;
  /** false nếu tốc độ dưới ngưỡng nên cửa sổ không bị xét. */
  applied: boolean;
  analysis: GaitAnalysis;
}
