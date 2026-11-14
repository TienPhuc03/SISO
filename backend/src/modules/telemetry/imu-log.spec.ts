import { IMU_WINDOW_SIZE } from './dto/telemetry-payload.dto';
import { adviseThresholds, evaluateLog, percentiles, summarizeByLabel } from './imu-calibration';
import { buildImuWindows, ImuLog, ImuLogLabel, NO_GPS_ACCURACY_M, parseImuLog, stripGps } from './imu-log';
import { renderMarkdown } from '../../scripts/imu-analyze';
import { syntheticWindow, SyntheticOptions } from './synthetic-imu.fixture';

/** Dựng nội dung log JSONL (như app ghi) từ mẫu tổng hợp, GPS 1 Hz với tốc độ [speed]. */
function logContent(label: ImuLogLabel, windows: number, opts: SyntheticOptions, speed: number, acc = 5): string {
  const count = windows * IMU_WINDOW_SIZE;
  const samples = syntheticWindow({ ...opts, count });
  const lines = [
    { k: 'h', v: 1, startedAt: '2026-11-12T01:00:00Z', label, note: 'tổng hợp', device: 'test', platform: 'test' },
    ...samples.map((s, i) => ({ k: 'a', t: i * 20, x: s.ax, y: s.ay, z: s.az })),
  ];
  for (let t = 0; t <= count * 20; t += 1000) {
    lines.push({ k: 'g', t, lat: 10.8, lng: 106.71, acc, spd: speed, mock: false } as never);
  }
  return lines.map((l) => JSON.stringify(l)).join('\n') + '\n';
}

const RUN = { stepHz: 2.7, stepAmplitudeG: 0.8, noiseG: 0.1 };
const MOTO = { vibrationHz: 10, vibrationAmplitudeG: 0.05, noiseG: 0.03 };
const WALK = { stepHz: 1.9, stepAmplitudeG: 0.4, noiseG: 0.05 };

describe('imu-log: đọc log và cắt cửa sổ (giống phía app)', () => {
  it('đọc header, gia tốc, GPS; sắp theo t', () => {
    const content = [
      '{"k":"h","v":1,"startedAt":"2026-11-12T01:00:00Z","label":"motorbike","note":"D2","device":"iOS","platform":"ios"}',
      '{"k":"g","t":1000,"lat":10.8,"lng":106.7,"acc":5,"spd":3.3,"mock":false}',
      '{"k":"a","t":20,"x":0,"y":0,"z":9.8}',
      '{"k":"a","t":0,"x":0,"y":0,"z":9.7}',
      '',
      '{"k":"magnet","t":1}',
    ].join('\n');
    const log = parseImuLog(content);
    expect(log.header).toMatchObject({ label: 'motorbike', note: 'D2', platform: 'ios' });
    expect(log.accel.map((a) => a.t)).toEqual([0, 20]);
    expect(log.gps[0]).toMatchObject({ t: 1000, spd: 3.3, acc: 5, mock: false, lat: 10.8 });
  });

  it('thiếu header hoặc dòng hỏng: báo lỗi rõ ràng', () => {
    expect(() => parseImuLog('{"k":"a","t":0,"x":0,"y":0,"z":9.8}')).toThrow('header');
    expect(() => parseImuLog('{"k":"h"}\n{"k":"a","t":0}')).toThrow('Dòng 2');
    expect(() => parseImuLog('{"k":"h"}\nkhông phải json')).toThrow('Dòng 2');
  });

  it('nhãn lạ đọc thành other', () => {
    expect(parseImuLog('{"k":"h","label":"bike"}').header.label).toBe('other');
  });

  it('stripGps bỏ lat/lng, giữ tốc độ và sai số; vẫn đọc lại được', () => {
    const stripped = stripGps(logContent('run', 1, RUN, 3.2));
    expect(stripped).not.toContain('"lat"');
    expect(stripped).not.toContain('"lng"');
    const log = parseImuLog(stripped);
    expect(log.gps[0]).toEqual({ t: 0, acc: 5, spd: 3.2, mock: false });
    expect(log.accel).toHaveLength(IMU_WINDOW_SIZE);
  });

  it('cắt cửa sổ 256 mẫu, bỏ phần lẻ; tốc độ trung bình bỏ -1, sai số tệ nhất, mock nếu có', () => {
    const log: ImuLog = {
      header: parseImuLog('{"k":"h","label":"run"}').header,
      accel: Array.from({ length: 600 }, (_, i) => ({ t: i * 20, x: 0, y: 0, z: 9.8 })),
      gps: [
        { t: 1000, acc: 4, spd: 2, mock: false },
        { t: 2000, acc: 30, spd: -1, mock: false },
        { t: 3000, acc: 6, spd: 4, mock: true },
      ],
    };
    const windows = buildImuWindows(log, 1_000_000);
    expect(windows).toHaveLength(2);
    expect(windows[0]).toMatchObject({ startT: 0, endT: 5100, averageSpeedMps: 3, horizontalAccuracy: 30, isMocked: true });
    expect(windows[0].samples[1].timestamp).toBe(1_000_020);
    // Cửa sổ 2 không có GPS: dùng lần gần nhất trước đó
    expect(windows[1]).toMatchObject({ averageSpeedMps: 4, horizontalAccuracy: 6 });
  });

  it('log không có GPS: tốc độ 0, sai số 999', () => {
    const log = parseImuLog(logContent('run', 1, RUN, 3.2).split('\n').filter((l) => !l.includes('"k":"g"')).join('\n'));
    expect(buildImuWindows(log)[0]).toMatchObject({ averageSpeedMps: 0, horizontalAccuracy: NO_GPS_ACCURACY_M });
  });
});

describe('imu-calibration: chạy đúng logic server trên log', () => {
  it('chạy bộ: mọi cửa sổ qua cổng, phiên không bị loại', () => {
    const e = evaluateLog('run.jsonl', parseImuLog(logContent('run', 4, RUN, 3.2)));
    expect(e.windows).toHaveLength(4);
    expect(e.windows.every((w) => w.biometric.applied && w.biometric.isValid)).toBe(true);
    expect(e.session.rejected).toBe(false);
    expect(e.accelRateHz).toBeCloseTo(50, 5);
  });

  it('xe máy: bị loại ERR_202 ở cửa sổ thứ 2 (luật 2 cửa sổ liên tiếp)', () => {
    const e = evaluateLog('moto.jsonl', parseImuLog(logContent('motorbike', 4, MOTO, 3.3)));
    expect(e.session).toMatchObject({ rejected: true, code: 'ERR_202', atWindow: 1, byKinematic: false });
    expect(e.session.atSeconds).toBeCloseTo(10.22, 2);
  });

  it('GPS sai số > 20 m: bị loại ngay ở Cổng Động học (ERR_203), tách khỏi lỗi sinh trắc', () => {
    const e = evaluateLog('gps.jsonl', parseImuLog(logContent('run', 2, RUN, 3.2, 35)));
    expect(e.session).toMatchObject({ rejected: true, code: 'ERR_203', atWindow: 0, byKinematic: true });
  });

  it('đi bộ chậm (< 2,5 m/s): không bị xét, không bị loại', () => {
    const e = evaluateLog('walk.jsonl', parseImuLog(logContent('walk', 3, WALK, 1.5)));
    expect(e.windows.every((w) => !w.biometric.applied)).toBe(true);
    expect(e.session.rejected).toBe(false);
  });

  it('tổng hợp theo nhãn và gợi ý ngưỡng: chạy bộ và xe máy tổng hợp tách được rõ', () => {
    const evals = [
      evaluateLog('run.jsonl', parseImuLog(logContent('run', 4, RUN, 3.2))),
      evaluateLog('moto.jsonl', parseImuLog(logContent('motorbike', 4, MOTO, 3.3))),
    ];
    const summaries = summarizeByLabel(evals);
    const run = summaries.find((s) => s.label === 'run');
    const moto = summaries.find((s) => s.label === 'motorbike');
    expect(run).toMatchObject({ logs: 1, windows: 4, appliedWindows: 4, biometricPassRate: 1, sessionsRejected: 0 });
    // Phiên xe máy dừng ở cửa sổ 2 nhưng thống kê vẫn tính cả 4 cửa sổ
    expect(moto).toMatchObject({ appliedWindows: 4, biometricFailRate: 1, sessionsRejected: 1 });
    expect(moto.rejectSeconds.min).toBeCloseTo(10.22, 2);

    const advice = adviseThresholds(summaries);
    const amp = advice.find((a) => a.metric === 'amplitudeG');
    expect(amp.separable).toBe(true);
    expect(amp.suggested).toBeGreaterThan(amp.motorbikeP95);
    expect(amp.suggested).toBeLessThan(amp.runP5);
    expect(amp.verdict).toContain('giữ nguyên');

    const md = renderMarkdown(evals, summaries, advice);
    expect(md).toContain('| run.jsonl | run |');
    expect(md).toContain('bị loại ERR_202 lúc 10.2 s');
  });

  it('thiếu dữ liệu xe máy: không gợi ý, nói rõ lý do', () => {
    const advice = adviseThresholds(
      summarizeByLabel([evaluateLog('run.jsonl', parseImuLog(logContent('run', 2, RUN, 3.2)))]),
    );
    expect(advice.every((a) => a.suggested === null && a.verdict.startsWith('Thiếu dữ liệu'))).toBe(true);
  });

  it('percentiles nội suy tuyến tính', () => {
    expect(percentiles([])).toBeNull();
    expect(percentiles([10, 20, 30, 40, 50])).toEqual({ p5: 12, median: 30, p95: 48 });
  });
});
