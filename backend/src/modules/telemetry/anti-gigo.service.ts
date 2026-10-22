import { Injectable } from '@nestjs/common';
import { ImuSampleDto } from './dto/telemetry-payload.dto';

export interface GigoCheckResult {
  isValid: boolean;
  errorCode: string | null;
  message: string;
  dominantFrequencyHz?: number;
  estimatedCadenceSpm?: number;
}

@Injectable()
export class AntiGigoService {
  private readonly MAX_HUMAN_SPEED_MPS = 9.0; // 32.4 km/h
  private readonly MIN_RUNNING_CADENCE_SPM = 120; // Bước/phút tối thiểu khi chạy
  private readonly MAX_RUNNING_CADENCE_SPM = 220; // Bước/phút tối đa

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
   * Tầng 2: Biometric Gate - Phân tích phổ tần số nhịp bước chân từ gia tốc kế
   * Tần số lấy mẫu: 50Hz. Cửa sổ: 256 mẫu (5.12s)
   */
  validateBiometrics(speedMps: number, imuSamples: ImuSampleDto[]): GigoCheckResult {
    // Nếu chạy chậm dưới 1 m/s (đi bộ nhẹ) hoặc không có đủ dữ liệu IMU thì bỏ qua kiểm tra FFT
    if (speedMps < 1.0 || !imuSamples || imuSamples.length < 64) {
      return { isValid: true, errorCode: null, message: 'Chạy chậm/chờ thêm mẫu' };
    }

    // 1. Tính gia tốc tổng hợp Amag = sqrt(ax^2 + ay^2 + az^2) - 1.0G
    const magnitudes = imuSamples.map((s) => {
      const mag = Math.sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az);
      return Math.abs(mag - 1.0); // Bỏ qua trọng lực Trái đất 1G
    });

    // 2. Tính phương sai / biên độ dao động đứng
    const avg = magnitudes.reduce((a, b) => a + b, 0) / magnitudes.length;
    const variance =
      magnitudes.reduce((acc, val) => acc + Math.pow(val - avg, 2), 0) / magnitudes.length;
    const amplitude = Math.sqrt(variance);

    // 3. Đếm số lần cắt qua giá trị trung bình (Zero-Crossing Rate) để ước tính tần số bước
    let zeroCrossings = 0;
    for (let i = 1; i < magnitudes.length; i++) {
      if ((magnitudes[i] - avg) * (magnitudes[i - 1] - avg) < 0) {
        zeroCrossings++;
      }
    }

    // Tần số bước chân = (số lần cắt / 2) / thời gian cửa sổ
    const durationSeconds = imuSamples.length / 50.0;
    const estimatedFreqHz = (zeroCrossings / 2) / durationSeconds;
    const estimatedCadenceSpm = Math.round(estimatedFreqHz * 60);

    // Người đi xe máy rà 10-15 km/h: Vận tốc cao (>= 2.5 m/s) nhưng nhịp bước gần như bằng 0 hoặc rung động cơ nhỏ
    if (speedMps >= 2.5) {
      if (amplitude < 0.2 || estimatedCadenceSpm < this.MIN_RUNNING_CADENCE_SPM) {
        return {
          isValid: false,
          errorCode: 'ERR_202',
          message: `VEHICLE_SPEED_MISMATCH: Tốc độ ${(speedMps * 3.6).toFixed(1)} km/h nhưng nhịp bước chỉ ${estimatedCadenceSpm} SPM (Nghi vấn đi xe máy).`,
          dominantFrequencyHz: Number(estimatedFreqHz.toFixed(2)),
          estimatedCadenceSpm,
        };
      }
    }

    return {
      isValid: true,
      errorCode: null,
      message: 'Nhịp bước chân sinh học hợp lệ.',
      dominantFrequencyHz: Number(estimatedFreqHz.toFixed(2)),
      estimatedCadenceSpm,
    };
  }
}
