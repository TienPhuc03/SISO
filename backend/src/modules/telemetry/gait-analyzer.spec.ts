import { analyzeGait, measureSampleRate } from './gait-analyzer';
import { SCENARIOS, syntheticWindow } from './synthetic-imu.fixture';

describe('analyzeGait (FFT Nhịp bước, mẫu tổng hợp)', () => {
  it('chạy bộ 2,7 Hz cho Nhịp bước ~162 SPM, biên độ lớn và đỉnh rõ', () => {
    const res = analyzeGait(SCENARIOS.running());

    expect(res.cadenceSpm).toBeGreaterThanOrEqual(159);
    expect(res.cadenceSpm).toBeLessThanOrEqual(165);
    expect(res.amplitudeG).toBeGreaterThan(0.5);
    expect(res.peakProminence).toBeGreaterThan(0.9);
  });

  it('nội suy parabol cho tần số giữa hai bin (3,2 Hz → ~192 SPM)', () => {
    const res = analyzeGait(syntheticWindow({ stepHz: 3.2, stepAmplitudeG: 1.0, noiseG: 0.1 }));

    expect(res.dominantFrequencyHz).toBeCloseTo(3.2, 1);
    expect(Math.abs(res.cadenceSpm - 192)).toBeLessThanOrEqual(3);
  });

  it('đi bộ nhanh 1,9 Hz cho ~114 SPM', () => {
    const res = analyzeGait(SCENARIOS.walking());

    expect(Math.abs(res.cadenceSpm - 114)).toBeLessThanOrEqual(3);
  });

  it('xe máy: biên độ dáng chạy rất nhỏ (dù FFT vẫn bắt được một đỉnh nhiễu trong dải)', () => {
    const res = analyzeGait(SCENARIOS.motorbike());

    // Không khẳng định độ rõ đỉnh: với nhiễu thuần nó dao động ~0,3–0,4 nên không phân biệt được.
    expect(res.amplitudeG).toBeLessThan(0.1);
  });

  it('rung động cơ mạnh 10 Hz (0,5G) không được tính vào biên độ dáng chạy', () => {
    const res = analyzeGait(syntheticWindow({ vibrationHz: 10, vibrationAmplitudeG: 0.5, noiseG: 0 }));

    expect(res.amplitudeG).toBeLessThan(0.05);
    expect(res.dominantFrequencyHz).toBeLessThanOrEqual(4.0);
  });

  it('chạy bộ trên nền rung 10 Hz vẫn giữ biên độ dáng chạy và Nhịp bước đúng', () => {
    const res = analyzeGait(
      syntheticWindow({ stepHz: 2.7, stepAmplitudeG: 0.8, vibrationHz: 10, vibrationAmplitudeG: 0.3, noiseG: 0.05 }),
    );

    expect(res.amplitudeG).toBeGreaterThan(0.5);
    expect(Math.abs(res.cadenceSpm - 162)).toBeLessThanOrEqual(3);
  });

  it('đứng yên: biên độ gần 0', () => {
    expect(analyzeGait(SCENARIOS.still()).amplitudeG).toBeLessThan(0.01);
  });

  it('tín hiệu hằng (không dao động) trả về 0, không chia cho 0', () => {
    const flat = syntheticWindow({ noiseG: 0 });

    expect(analyzeGait(flat)).toMatchObject({ cadenceSpm: 0, amplitudeG: 0, peakProminence: 0 });
  });

  it('dùng tần số lấy mẫu thật từ timestamp (máy chỉ đạt 48 Hz)', () => {
    const res = analyzeGait(syntheticWindow({ stepHz: 2.7, stepAmplitudeG: 0.8, sampleRateHz: 48 }));

    expect(res.sampleRateHz).toBeCloseTo(48, 0);
    expect(Math.abs(res.cadenceSpm - 162)).toBeLessThanOrEqual(3);
  });

  it('timestamp không dùng được thì quay về 50 Hz', () => {
    const samples = syntheticWindow().map((s) => ({ ...s, timestamp: 0 }));

    expect(measureSampleRate(samples)).toEqual({ sampleRateHz: 50, windowSeconds: 5.12 });
  });

  it('không có mẫu nào thì trả về 0', () => {
    expect(analyzeGait([])).toMatchObject({ cadenceSpm: 0, amplitudeG: 0 });
  });
});
