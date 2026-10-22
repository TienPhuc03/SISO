import { AntiGigoService } from './anti-gigo.service';

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

  describe('Biometric Gate (Tầng 2 - Bước chân chống xe máy)', () => {
    it('phải từ chối người ngồi xe máy rà 12km/h (3.3 m/s) với dao động cơ nhỏ và không có nhịp bước', () => {
      // Giả lập 256 mẫu dao động nhỏ trên xe máy (ax=0.01, ay=0.01, az=1.0)
      const samples = Array.from({ length: 256 }, (_, i) => ({
        ax: 0.01 * Math.sin(i * 0.1),
        ay: 0.01 * Math.cos(i * 0.1),
        az: 1.0 + 0.02 * Math.sin(i * 0.2),
        timestamp: Date.now() + i * 20,
      }));

      const res = service.validateBiometrics(3.3, samples);
      expect(res.isValid).toBe(false);
      expect(res.errorCode).toBe('ERR_202');
    });
  });
});
