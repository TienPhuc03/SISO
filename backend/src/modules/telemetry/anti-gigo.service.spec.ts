import { AntiGigoService, BIOMETRIC_THRESHOLDS } from './anti-gigo.service';
import { SCENARIOS, syntheticWindow } from './synthetic-imu.fixture';

describe('AntiGigoService (GIGO Engine Unit Tests)', () => {
  let service: AntiGigoService;

  beforeEach(() => {
    service = new AntiGigoService();
  });

  describe('Kinematic Gate (Tầng 1)', () => {
    it('phải từ chối nếu có cờ Fake GPS (isMocked = true)', () => {
      const res = service.validateKinematics(3.0, 5.0, true);
      expect(res.isValid).toBe(false);
      expect(res.errorCode).toBe('ERR_201');
    });

    it('phải từ chối nếu vận tốc vượt quá 9.0 m/s (32.4 km/h)', () => {
      const res = service.validateKinematics(12.0, 5.0, false);
      expect(res.isValid).toBe(false);
      expect(res.errorCode).toBe('ERR_202');
    });

    it('phải chấp nhận vận tốc chạy bộ hợp lệ (3.5 m/s)', () => {
      const res = service.validateKinematics(3.5, 5.0, false);
      expect(res.isValid).toBe(true);
    });
  });

  describe('Cổng Sinh trắc (Tầng 2, một cửa sổ)', () => {
    it('chạy bộ thật ở 3,2 m/s: qua, kèm Nhịp bước để hiện HUD', () => {
      const res = service.validateBiometrics(3.2, SCENARIOS.running());

      expect(res.isValid).toBe(true);
      expect(res.applied).toBe(true);
      expect(res.analysis.cadenceSpm).toBeGreaterThan(150);
    });

    it('xe máy rà 12 km/h (3,3 m/s): không qua với ERR_202', () => {
      const res = service.validateBiometrics(3.3, SCENARIOS.motorbike());

      expect(res.isValid).toBe(false);
      expect(res.errorCode).toBe('ERR_202');
      expect(res.message).toContain('biên độ');
    });

    it('điện thoại gắn trên xe máy rung mạnh 10 Hz (0,5G) vẫn bị bắt: rung ngoài dải không tính là bước chân', () => {
      const res = service.validateBiometrics(
        3.3,
        syntheticWindow({ vibrationHz: 10, vibrationAmplitudeG: 0.5, noiseG: 0.03 }),
      );

      expect(res.isValid).toBe(false);
      expect(res.errorCode).toBe('ERR_202');
    });

    it('nhịp đi bộ (~114 SPM) mà tốc độ chạy 3 m/s: không qua vì Nhịp bước dưới 120', () => {
      const res = service.validateBiometrics(3.0, SCENARIOS.walking());

      expect(res.isValid).toBe(false);
      expect(res.message).toContain('Nhịp bước');
    });

    it('dưới 2,5 m/s thì không xét (đi bộ hợp lệ), nhưng vẫn trả phân tích', () => {
      const res = service.validateBiometrics(1.6, SCENARIOS.walking());

      expect(res.isValid).toBe(true);
      expect(res.applied).toBe(false);
      expect(res.analysis.cadenceSpm).toBeGreaterThan(100);
    });

    it('đúng tại ngưỡng 2,5 m/s thì bắt đầu xét', () => {
      const res = service.validateBiometrics(BIOMETRIC_THRESHOLDS.minSpeedMps, SCENARIOS.still());

      expect(res.applied).toBe(true);
      expect(res.isValid).toBe(false);
    });
  });
});
